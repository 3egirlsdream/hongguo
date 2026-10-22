package core

import (
	"crypto/md5"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"math/bits"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

func hgAuthHex(s string) []byte {
	b, e := hex.DecodeString(s)
	if e != nil {
		panic(e)
	}
	return b
}
func hgAuthLE(v uint32) []byte { return binary.LittleEndian.AppendUint32(nil, v) }
func hgAuthRand() (uint32, error) {
	var b [4]byte
	_, e := rand.Read(b[:])
	return binary.LittleEndian.Uint32(b[:]), e
}
func hgAuthFold(seed uint32, data []byte) uint32 {
	for i, b := range data {
		if i%2 == 0 {
			seed ^= seed>>4 ^ seed<<6 ^ uint32(b)
		} else {
			seed = ^(seed>>7 ^ seed ^ (seed<<12 | uint32(b)))
		}
	}
	return seed
}
func hgAuthDigest(q string, b []byte, t uint32) (uint32, [32]byte, [16]byte) {
	h := hongguoSM3([]byte(q))
	var m [16]byte
	if len(b) > 0 {
		m = md5.Sum(b)
	}
	v := hgAuthFold(0x20230928, h[:])
	v = hgAuthFold(v, m[:])
	return hgAuthFold(v, hgAuthLE(t)), h, m
}
func hgAuthF13(v, t uint32, h [32]byte, m [16]byte) []byte {
	g := int(((v & 15) - 2) / 3)
	counter := t + [...]uint32{0x8980f29b, 0xeb549c7f, 0xb08726db, 0xd40cb5e6, 0xe8f559e4}[g]
	message := append(append(append([]byte{}, h[:]...), m[:]...), hgAuthLE(t)...)
	for _, b := range hgAuthHex("8496779dd4150bf8") {
		message = append(message, byte(uint16(b)*257>>((counter+5)&7)))
	}
	message = append(message, 160, 1, 0, 0)
	initial := [4]uint32{0x79e0f2fb, 0xc8b52570, 0xebc2f8cd, 0x7c104d93}
	mask := [4]uint32{0x19be4866, 0xe85986b4, 0xe19b326e, 0x71d1d7d4}
	for i := 0; i < 4; i++ {
		initial[i] = bits.RotateLeft32(initial[i], -int(counter&31))
		mask[i] = bits.RotateLeft32(mask[i], -int((counter+6)&31))
	}
	state := initial
	rotations := [16]int{7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21}
	for r := 0; r < 64; r++ {
		a, b, c, d := state[0], state[1], state[2], state[3]
		var f uint32
		switch r / 16 {
		case 0:
			f = b&c | ^b&d
		case 1:
			f = b&d | c&^d
		case 2:
			f = b ^ c ^ d
		case 3:
			f = c ^ (b | ^d)
		}
		word := binary.LittleEndian.Uint32(message[int(hgAuthWordOrder[g*64+r])*4:])
		k := bits.RotateLeft32(hgAuthRoundWords[r], -int((counter+1)&31))
		state = [4]uint32{d, b + bits.RotateLeft32(a+f+word+k, rotations[(r/16)*4+r%4]), b, c}
	}
	result := []byte{}
	for i, x := range state {
		result = append(result, hgAuthLE((initial[i]+x)^mask[i])...)
	}
	checksum := uint32(0x20220420)
	for i, b := range result[:12] {
		if i%2 == 0 {
			checksum ^= checksum>>3 ^ uint32(b) ^ checksum<<7
		} else {
			checksum ^= checksum>>5 ^ ^(uint32(b) | checksum<<11)
		}
	}
	return append(result, hgAuthLE((checksum|4)^0x1000000)...)
}
func hgAuthHelios(t, nonce uint32) string {
	digest := md5.Sum(append(hgAuthLE(nonce), []byte("8662")...))
	ascii := []byte(hex.EncodeToString(digest[:]))
	k := binary.LittleEndian.Uint64(ascii)
	queue := []uint64{binary.LittleEndian.Uint64(ascii[8:]), binary.LittleEndian.Uint64(ascii[16:]), binary.LittleEndian.Uint64(ascii[24:])}
	keys := []uint64{k}
	for i := 0; i < 33; i++ {
		v := (bits.RotateLeft64(queue[0], -8) + k) ^ uint64(i)
		queue = append(queue[1:], v)
		k = v ^ bits.RotateLeft64(k, 3)
		keys = append(keys, k)
	}
	data := hongguoCommentPad([]byte(fmt.Sprintf("%d-1588093228-8662", t)))
	result := hgAuthLE(nonce)
	for off := 0; off < len(data); off += 16 {
		x, y := binary.LittleEndian.Uint64(data[off:]), binary.LittleEndian.Uint64(data[off+8:])
		for _, k := range keys {
			y = k ^ (x + bits.RotateLeft64(y, -8))
			x = y ^ bits.RotateLeft64(x, 3)
		}
		result = binary.LittleEndian.AppendUint64(result, x)
		result = binary.LittleEndian.AppendUint64(result, y)
	}
	return base64.StdEncoding.EncodeToString(result)
}
func hgAuthGorgon(q string, body []byte, t uint32, n uint16) string {
	qh := md5.Sum([]byte(q))
	var bh [16]byte
	if len(body) > 0 {
		bh = md5.Sum(body)
	}
	data := make([]byte, 20)
	copy(data, qh[:4])
	copy(data[4:], bh[:4])
	binary.LittleEndian.PutUint32(data[12:], 67503104)
	binary.BigEndian.PutUint32(data[16:], t)
	key := [8]byte{74, 64, 22, byte(n >> 8), 71, 108, 1, byte(n)}
	var box [256]byte
	for i := range box {
		box[i] = byte(i)
	}
	j := byte(0)
	for i := range box {
		j += box[i] + key[i%8]
		box[i] = box[j]
	}
	j = 0
	for i := range data {
		j += box[i+1]
		box[i+1] = box[j]
		data[i] ^= box[box[i+1]*2]
	}
	for i := range data {
		data[i] = bits.RotateLeft8(data[i], 4)
		data[i] = ^(bits.Reverse8(data[i]^data[(i+1)%20]) ^ 20)
	}
	return hex.EncodeToString(append([]byte{132, 4, byte(n), byte(n >> 8), 64, 1}, data...))
}

type hgAuthProto []byte

func (p *hgAuthProto) number(f int, n int64) {
	*p = binary.AppendUvarint(*p, uint64(f<<3))
	*p = binary.AppendUvarint(*p, uint64(n<<1)^uint64(n>>63))
}
func (p *hgAuthProto) data(f int, v []byte) {
	if len(v) == 0 {
		return
	}
	*p = binary.AppendUvarint(*p, uint64(f<<3|2))
	*p = binary.AppendUvarint(*p, uint64(len(v)))
	*p = append(*p, v...)
}
func (p *hgAuthProto) text(f int, v string) { p.data(f, []byte(v)) }
func (p *hgAuthProto) numbers(values [][2]int64) {
	for _, v := range values {
		p.number(int(v[0]), v[1])
	}
}
func hgAuthEnvelope(q string, t, n uint32, did string, h [32]byte, m [16]byte, f13 []byte) []byte {
	var device, report, env, count, out hgAuthProto
	device.numbers([][2]int64{{1, 1}, {2, 2}})
	for _, v := range []struct {
		k int
		v string
	}{{3, "8662"}, {4, did}, {5, "Ai6svO3PyrwDOUSmO6ZcResxu"}, {6, "!noperm!"}} {
		device.text(v.k, v.v)
	}
	device.numbers([][2]int64{{7, -888888}, {8, -888888}, {9, 3}, {10, -888888}})
	device.text(11, "!notset!")
	device.text(12, "Asia/Shanghai,8")
	device.text(13, "zh_CN")
	device.number(14, 4)
	for i, v := range []float32{255.24993896484375, 35.58599090576172, 3.467449188232422, 3.467449188232422, 255.1754913330078, 42.17544174194336} {
		device = binary.AppendUvarint(device, uint64((i+16)<<3|5))
		device = binary.LittleEndian.AppendUint32(device, math.Float32bits(v))
	}
	device.text(22, "16")
	device.number(23, 41)
	device.number(24, 36)
	for i := 25; i < 29; i++ {
		stamp := int64(1728388016635)
		if i == 28 {
			stamp += 2
		}
		device.number(i, stamp)
	}
	device.number(29, -1)
	for i, v := range []string{"25053RT47C", "Redmi", "25053RT47C", "25053RT47C", "Redmi", "Redmi", "Redmi"} {
		device.text(i+30, v)
	}
	device.number(38, 31)
	report.numbers([][2]int64{{1, int64(t)}, {2, -2}, {4, 200}})
	env.numbers([][2]int64{{1, 110}, {2, 146331399}, {3, 146331396}, {5, 7}})
	env.text(6, "v04.06.04.03-bugfix")
	env.number(7, 11001)
	env.data(12, device)
	env.data(13, report)
	env.text(14, "7.3.5.32")
	count.numbers([][2]int64{{1, 111}, {2, 10}, {3, 694367}, {5, 586952199}})
	out.data(1, hgAuthHex("f7e85ffad7d7dc3bd62ac87057cf6118"))
	out.number(2, 3)
	out.number(3, int64(n))
	for _, v := range []struct {
		k int
		v string
	}{{4, "8662"}, {5, did}, {6, "1588093228"}, {7, "7.3.5.32"}, {8, "v04.06.04-ml-android"}} {
		out.text(v.k, v.v)
	}
	out.number(9, 67503104)
	out.data(10, hgAuthHex("4001000000000000"))
	out.number(12, int64(t))
	out.data(13, f13)
	out.data(14, h[:6])
	out.data(15, count)
	out.text(16, "AXYQOS6n2m60x1fVZHIrH3iol")
	out.number(17, int64(t))
	digest := hongguoSM3(append(append(append([]byte{}, []byte(q)...), m[:]...), []byte("none")...))
	out.data(19, digest[:])
	out.text(20, "none")
	out.number(21, 312)
	out.data(23, env)
	out.text(24, `{"cmr":16777216,"cmr2":16777216,"un_h":1879194040,"vpn":0,"kd":0,"fkd":3672518972,"pd":-1872573247,"dyn":"","do":0,"tk":true}`)
	return out
}
func hgAuthScramble(data, key []byte) []byte {
	result := make([]byte, len(data))
	for i, b := range data {
		a, c := key[i*4&28], key[(i*4&28)+1]
		v := ^(bits.RotateLeft8(b, 4) + a) ^ c
		result[len(data)-i-1] = ^((bits.RotateLeft8(v, 3) + c) ^ a)
	}
	end := len(result) - 1
	flag := result[end] ^ result[end-1]
	first := result[0]
	result[0] += ^flag
	result[1] += result[0] ^ result[end] ^ 254
	result[2] += (flag - first) ^ bits.RotateLeft8(result[1], 3) ^ 2
	for i := 3; i < end; i++ {
		result[i] += ^(bits.RotateLeft8(result[i-1], 3) ^ result[i-2] ^ byte(i))
	}
	result[end] ^= result[end-1]
	var sum byte
	for _, b := range result[1:] {
		sum += b
	}
	result[0] = (result[0] ^ result[1]) + sum
	return result
}
func hgAuthAES(data []byte, t uint32) ([]byte, error) {
	if len(data) < 248 {
		return nil, errors.New("账号签名数据不完整")
	}
	branch := int(t & 3)
	sbox := hgAuthBoxes[branch*256 : (branch+1)*256]
	lanes := [4][4]int{{1, 0, 2, 3}, {2, 0, 3, 1}, {0, 1, 3, 2}, {1, 0, 2, 3}}[branch]
	permutation := [4][16]int{{0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3}, {0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11}, {0, 9, 14, 7, 4, 13, 2, 11, 8, 1, 6, 3, 12, 5, 10, 15}, {0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3}}[branch]
	seed := [4]uint32{0xca025ddc, 0x823dc546, 0xc9420583, 0xc298225f}[branch]
	key := hgAuthHex("f1593376766ea98d34f31b057a9d5be4")
	var schedule [48]byte
	for i := range key {
		schedule[i] = key[i] ^ byte(seed>>uint(i%4*8))
	}
	for w := 4; w < 12; w++ {
		var prev [4]byte
		copy(prev[:], schedule[(w-1)*4:w*4])
		if w%4 == 0 {
			prev = [4]byte{sbox[prev[1]] ^ byte(seed>>uint((8+(w-4)*2)&24)), sbox[prev[2]], sbox[prev[3]], sbox[prev[0]]}
		}
		for j := 0; j < 4; j++ {
			schedule[w*4+j] = prev[j] ^ schedule[(w-4)*4+j]
		}
	}
	encrypt := func(input []byte) []byte {
		b := append([]byte{}, input...)
		add := func(round int) {
			for i := range b {
				b[i] ^= schedule[round*16+i/4*4+lanes[i%4]]
			}
		}
		add(0)
		for r := 1; r <= 2; r++ {
			old := append([]byte{}, b...)
			for i, p := range permutation {
				b[i] = sbox[old[lanes[p/4]*4+p%4]]
			}
			if r == 1 {
				copy(old, b)
				for i := range b {
					b[i] = old[i/4*4+lanes[i%4]]
				}
				xt := func(v byte) byte {
					r := v << 1
					if v&128 != 0 {
						r ^= 27
					}
					return r
				}
				for col := 0; col < 4; col++ {
					v := [4]byte{b[col], b[col+4], b[col+8], b[col+12]}
					sum := v[0] ^ v[1] ^ v[2] ^ v[3]
					for row := 0; row < 4; row++ {
						b[row*4+col] = v[row] ^ sum ^ xt(v[row]^v[(row+1)%4])
					}
				}
			}
			add(r)
		}
		for i := range b {
			b[i] ^= schedule[16+i]
		}
		return b
	}
	extracted := make([]byte, 32)
	for i := 0; i < 31; i++ {
		chunk := data[i*8:]
		extracted[i] = chunk[0]>>4&2 | chunk[1]&64 | chunk[2]>>2&1 | chunk[3]<<3&128 | chunk[4]>>1&4 | chunk[5]<<3&16 | chunk[6]<<5&32 | chunk[7]>>4&8
	}
	extracted[31] = 1
	previous := hgAuthHex("1fe109a4125283f418de9e051a969e12")
	encrypted := []byte{}
	for off := 0; off < 32; off += 16 {
		for i := 0; i < 16; i++ {
			extracted[off+i] ^= previous[i]
		}
		previous = encrypt(extracted[off : off+16])
		encrypted = append(encrypted, previous...)
	}
	out := append([]byte{encrypted[31]}, data...)
	for i, k := range encrypted[:31] {
		chunk := out[1+i*8:]
		chunk[0] = chunk[0]&^32 | k<<4&32
		chunk[1] = chunk[1]&^64 | k&64
		chunk[2] = chunk[2]&^4 | k<<2&4
		chunk[3] = chunk[3]&^16 | k>>3&16
		chunk[4] = chunk[4]&^8 | k<<1&8
		chunk[5] = chunk[5]&^2 | k>>3&2
		chunk[6] = chunk[6]&^1 | k>>5&1
		chunk[7] = chunk[7]&127 | k<<4&128
	}
	return out, nil
}
func hgAuthSign(q url.Values, body []byte, stamp int64, did string) (string, http.Header, error) {
	t := uint32(stamp / 1000)
	var raw string
	var iv uint32
	var hash [32]byte
	var md [16]byte
	found := false
	for ticket := stamp; ticket < stamp+256; ticket++ {
		q.Set("_rticket", strconv.FormatInt(ticket, 10))
		raw = q.Encode()
		iv, hash, md = hgAuthDigest(raw, body, t)
		if (iv&15)%3 == 2 {
			found = true
			break
		}
	}
	if !found {
		return "", nil, errors.New("无法准备红果账号签名")
	}
	var random [4]uint32
	for i := range random {
		n, e := hgAuthRand()
		if e != nil {
			return "", nil, e
		}
		random[i] = n
	}
	f13 := hgAuthF13(iv, t, hash, md)
	payload := hgAuthEnvelope(raw, t, random[0], did, hash, md, f13)
	signKey := hgAuthHex("8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eaef71cb691f7aa8aa2f5")
	derived := hongguoSM3(append(append(append([]byte{}, signKey...), hgAuthLE(random[1])...), signKey...))
	mixed := append(hgAuthHex("4001000000000000"), hgAuthScramble(payload, derived[:])...)
	for l, r := 0, len(mixed)-1; l < r; l, r = l+1, r-1 {
		mixed[l], mixed[r] = mixed[r], mixed[l]
	}
	b := (random[1] >> 16) & 255
	mask := hgAuthLE(^((b << 11) | (random[1] >> 24) ^ (b >> 5) ^ b))
	for i := range mixed {
		mixed[i] ^= mask[(^i)&3]
	}
	check := uint32(0x18000001) | uint32(hash[0]&63)<<14 | uint32(f13[0]&63)<<8
	container := append(append(append([]byte{53}, hgAuthLE(random[2])...), hgAuthLE(check)...), mixed...)
	container = append(container, hgAuthLE(random[1])[2:]...)
	encrypted, e := hgAuthAES(container, t)
	if e != nil {
		return "", nil, e
	}
	header := hgAuthHex("03000000f7e85ffad7d7dc3bd62ac87057cf6118")
	for i := 0; i < 20; i += 4 {
		binary.LittleEndian.PutUint32(header[i:], binary.LittleEndian.Uint32(header[i:])^t)
	}
	header = append(header, hgAuthLE(random[1])[:2]...)
	header = append(header, 0, 1)
	result := http.Header{}
	result.Set("X-Medusa", base64.StdEncoding.EncodeToString(append(header, encrypted...)))
	result.Set("X-Helios", hgAuthHelios(t, random[3]))
	result.Set("X-Gorgon", hgAuthGorgon(raw, body, t, uint16(random[0])))
	result.Set("X-Khronos", strconv.FormatUint(uint64(t), 10))
	result.Set("X-SS-Req-Ticket", q.Get("_rticket"))
	if len(body) > 0 {
		result.Set("X-SS-STUB", strings.ToUpper(hex.EncodeToString(md[:])))
	}
	return raw, result, nil
}
