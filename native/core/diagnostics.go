package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"

	"sync"
	"time"
)

const diagnosticLogBytes = 5 * 1024 * 1024

const diagnosticLogBackups = 2

type diagnosticEvent struct {
	TraceID            string    `json:"traceId,omitempty"`
	Stage              string    `json:"stage,omitempty"`
	ElapsedMS          int64     `json:"elapsedMs,omitempty"`
	TotalMS            int64     `json:"totalMs,omitempty"`
	HTTPStatus         int       `json:"httpStatus,omitempty"`
	Client             string    `json:"client,omitempty"`
	Protocol           string    `json:"protocol,omitempty"`
	CFRay              string    `json:"cfRay,omitempty"`
	ResponseType       string    `json:"responseType,omitempty"`
	RequestedQuality   int       `json:"requestedQuality,omitempty"`
	Time               time.Time `json:"time"`
	Level              string    `json:"level"`
	Event              string    `json:"event"`
	Source             string    `json:"source,omitempty"`
	DramaID            string    `json:"dramaId,omitempty"`
	DramaTitle         string    `json:"dramaTitle,omitempty"`
	Episode            int       `json:"episode,omitempty"`
	Run                uint64    `json:"run,omitempty"`
	StartSeconds       float64   `json:"startSeconds,omitempty"`
	Host               string    `json:"host,omitempty"`
	OffsetBytes        int64     `json:"offsetBytes,omitempty"`
	TotalBytes         int64     `json:"totalBytes,omitempty"`
	Attempt            int       `json:"attempt,omitempty"`
	Quality            int       `json:"quality,omitempty"`
	AvailableQualities []int     `json:"availableQualities,omitempty"`
	Message            string    `json:"message"`
}

type diagnosticLog struct {
	mu          sync.Mutex
	path        string
	limit       int64
	warningOnce sync.Once
}

func newDiagnosticLog(directory string) *diagnosticLog {
	return &diagnosticLog{path: filepath.Join(directory, "logs", "app.log"), limit: diagnosticLogBytes}
}

func (log *diagnosticLog) write(event diagnosticEvent) error {
	event.Time = time.Now()
	if event.Level == "" {
		event.Level = "error"
	}
	data, err := json.Marshal(event)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	log.mu.Lock()
	defer log.mu.Unlock()
	if int64(len(data)) > log.limit {
		return errors.New("单条诊断日志过大")
	}
	if err := os.MkdirAll(filepath.Dir(log.path), 0700); err != nil {
		return err
	}
	info, err := os.Stat(log.path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if info != nil && info.Size()+int64(len(data)) > log.limit {
		if err := log.rotate(); err != nil {
			return err
		}
	}
	file, err := os.OpenFile(log.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		return err
	}
	_, writeErr := file.Write(data)
	return errors.Join(writeErr, file.Close())
}

func (log *diagnosticLog) rotate() error {
	oldest := log.path + "." + strconv.Itoa(diagnosticLogBackups)
	if err := os.Remove(oldest); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	for index := diagnosticLogBackups; index > 0; index-- {
		previous := log.path
		if index > 1 {
			previous += "." + strconv.Itoa(index-1)
		}
		if err := os.Rename(previous, log.path+"."+strconv.Itoa(index)); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	return nil
}

var diagnosticCredential = regexp.MustCompile(`(?i)(?:x-tt-token|token|access_token|refresh_token|sessionid|decryption_key|decryptionKey|password|secret)\s*[=:]\s*(?:"[^"]*"|'[^']*'|[^\s,;}\]]+)`)

func redactDiagnosticMessage(message string) string {
	message = rePublicURL.ReplaceAllStringFunc(message, func(raw string) string {
		parsed, err := url.Parse(raw)
		if err != nil || parsed.Hostname() == "" {
			return "[address hidden]"
		}
		return "[host " + parsed.Hostname() + "]"
	})
	return diagnosticCredential.ReplaceAllString(message, "[credential hidden]")
}

func (downloader *Downloader) recordDiagnostic(event diagnosticEvent) {
	if downloader == nil || downloader.diagnostics == nil {
		return
	}
	event.Message = truncate(redactDiagnosticMessage(event.Message), 4096)
	event.DramaTitle = truncate(redactDiagnosticMessage(event.DramaTitle), 256)
	if err := downloader.diagnostics.write(event); err != nil {
		downloader.diagnostics.warningOnce.Do(func() {
			fmt.Fprintf(os.Stderr, "诊断日志保存失败：%v\n", publicError(err))
		})
	}
}
