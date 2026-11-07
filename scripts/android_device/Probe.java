package com.duanju.historyprobe;
import android.app.Instrumentation;
import android.os.Bundle;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.telephony.SmsManager;
import android.telephony.SubscriptionManager;
import android.telephony.SubscriptionInfo;
import android.view.accessibility.AccessibilityNodeInfo;
import android.graphics.Rect;
import org.json.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;
public class Probe extends Instrumentation {
    private Bundle args;
    private String library;
    private static native String nativeCall(String library,String input);
    private JSONObject call(JSONObject input) throws Exception {
        JSONObject result=new JSONObject(nativeCall(library,input.toString()));
        if(!result.optBoolean("ok"))throw new Exception("native_request_failed");
        return result.getJSONObject("data");
    }
    private void initialize() throws Exception {
        System.load(getContext().getApplicationInfo().nativeLibraryDir+"/libguo_probe.so");
        library=getTargetContext().getApplicationInfo().nativeLibraryDir+"/libduanju_core.so";
        call(new JSONObject().put("action","initialize").put("directory",getTargetContext().getFilesDir().getAbsolutePath()));
    }
    private JSONObject account(String command,JSONObject input) throws Exception {
        return call(new JSONObject().put("action","hongguoAccount").put("profile","default").put("command",command).put("account",input));
    }
    private String read(File file) throws Exception {
        return new String(Files.readAllBytes(file.toPath()),"UTF-8");
    }
    private void write(File file,String text) throws Exception {
        file.getParentFile().mkdirs();
        Files.write(file.toPath(),text.getBytes("UTF-8"));
    }
    private File backupRoot() {
        return new File(getTargetContext().getCacheDir(),"guo-device-fixture");
    }
    private void backup(File file,String key) throws Exception {
        File root=backupRoot();
        root.mkdirs();
        File marker=new File(root,key+".exists");
        write(marker,Boolean.toString(file.exists()));
        if(file.exists())Files.copy(file.toPath(),new File(root,key).toPath(),StandardCopyOption.REPLACE_EXISTING);
    }
    private void restoreFile(File target,String key) throws Exception {
        File root=backupRoot();
        File marker=new File(root,key+".exists");
        if(!marker.exists())throw new Exception("fixture_backup_missing");
        if(Boolean.parseBoolean(read(marker))) {
            target.getParentFile().mkdirs();
            Files.copy(new File(root,key).toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);
        }
        else Files.deleteIfExists(target.toPath());
    }
    private JSONObject fixture(boolean restore) throws Exception {
        File root=backupRoot();
        File settings=new File(getTargetContext().getFilesDir(),"resource-settings.json");
        SharedPreferences prefs=getTargetContext().getSharedPreferences("playback_continuity",Context.MODE_PRIVATE);
        if(restore) {
            JSONObject info=new JSONObject(read(new File(root,"fixture.json")));
            File media=new File(info.getString("media"));
            restoreFile(media,"media");
            restoreFile(settings,"settings");
            Files.deleteIfExists(new File(media.getParentFile(),"guo-device-synthetic.mp4").toPath());
            SharedPreferences.Editor edit=prefs.edit();
            for(String key:new String[] {
                "snapshot","owner"
            }
            ) {
                if(info.has(key))edit.putString(key,info.getString(key));
                else edit.remove(key);
            }
            edit.commit();
            SharedPreferences flutter=getTargetContext().getSharedPreferences("FlutterSharedPreferences",Context.MODE_PRIVATE);
            String raw=flutter.getString("flutter.localSnapshot.v1",null);
            if(raw!=null) {
                JSONObject snapshot=new JSONObject(raw),values=snapshot.getJSONObject("values");
                Iterator<String> keys=values.keys();
                while(keys.hasNext()) {
                    String key=keys.next();
                    Object value=values.get(key);
                    if(!(value instanceof String))continue;
                    String text=(String)value;
                    try {
                        if(text.startsWith("[")) {
                            JSONArray rows=new JSONArray(text),kept=new JSONArray();
                            for(int i=0;i<rows.length();i++) {
                                String row=String.valueOf(rows.get(i));
                                if(!row.contains("guo-device-synthetic")&&!row.contains("hongguo:device-fixture"))kept.put(rows.get(i));
                            }
                            values.put(key,kept.toString());
                        }
                        else if(text.startsWith("{")) {
                            JSONObject rows=new JSONObject(text);
                            rows.remove("guo-device-synthetic");
                            rows.remove("hongguo:device-fixture");
                            values.put(key,rows.toString());
                        }
                    }
                    catch(JSONException ignored) {
                    }
                }
                flutter.edit().putString("flutter.localSnapshot.v1",snapshot.toString()).commit();
            }
            for(File file:root.listFiles())file.delete();
            root.delete();
            return new JSONObject().put("restored",true);
        }
        if(new File(root,"fixture.json").exists())throw new Exception("restore_existing_fixture_first");
        initialize();
        File media=new File(call(new JSONObject().put("action","downloadDirectory")).getString("directory"),"media-library.json");
        backup(settings,"settings");
        backup(media,"media");
        JSONObject info=new JSONObject().put("media",media.getAbsolutePath());
        for(String key:new String[] {
            "snapshot","owner"
        }
        )if(prefs.contains(key))info.put(key,prefs.getString(key,""));
        write(new File(root,"fixture.json"),info.toString());
        JSONObject resource=settings.exists()?new JSONObject(read(settings)):new JSONObject().put("catalogConcurrency",3).put("catalogIntervalMs",250).put("downloadConcurrency",2);
        resource.put("proxyMode","manual").put("proxyUrl","http://127.0.0.1:9");
        write(settings,resource.toString());
        File video=new File(media.getParentFile(),"guo-device-synthetic.mp4");
        video.getParentFile().mkdirs();
        Files.copy(new File(args.getString("video")).toPath(),video.toPath(),StandardCopyOption.REPLACE_EXISTING);
        JSONObject drama=new JSONObject().put("id","hongguo:device-fixture").put("source","hongguo").put("sourceId","device-fixture").put("title","合成视频 · 界面验证").put("episodes",1);
        JSONObject item=new JSONObject().put("id","guo-device-synthetic").put("drama",drama).put("file",video.getName()).put("kind","episode").put("episodes",new JSONArray().put(1)).put("duration",180).put("bytes",video.length()).put("created",java.time.Instant.now().toString());
        JSONObject data=media.exists()?new JSONObject(read(media)):new JSONObject().put("items",new JSONArray());
        data.getJSONArray("items").put(item);
        write(media,data.toString());
        JSONObject snapshot=new JSONObject().put("schema",1).put("profile","default").put("drama",drama).put("episodeId","guo-device-synthetic").put("episodeNumber",1).put("position",0).put("playing",true).put("localOnly",true).put("allowOnlineFallback",false).put("fullscreen",true).put("mediaId","guo-device-synthetic").put("updatedAt",System.currentTimeMillis());
        prefs.edit().putString("snapshot",snapshot.toString()).putString("owner","device-fixture").commit();
        return new JSONObject().put("fixture_ready",true).put("external_requests_blocked",true);
    }
    private void nodes(AccessibilityNodeInfo node,JSONArray out) throws Exception {
        if(node==null||!node.isVisibleToUser())return;
        CharSequence text=node.getText(),desc=node.getContentDescription();
        if(text!=null||desc!=null) {
            Rect r=new Rect();
            node.getBoundsInScreen(r);
            JSONObject row=new JSONObject().put("text",text==null?"":text.toString()).put("description",desc==null?"":desc.toString()).put("clickable",node.isClickable()).put("bounds",new JSONArray().put(r.left).put(r.top).put(r.right).put(r.bottom));
            if(node.getRangeInfo()!=null)row.put("value",node.getRangeInfo().getCurrent());
            out.put(row);
        }
        for(int i=0;i<node.getChildCount();i++)nodes(node.getChild(i),out);
    }
    private boolean click(AccessibilityNodeInfo node,String value) {
        if(node==null||!node.isVisibleToUser())return false;
        if(value.equals(String.valueOf(node.getText()))||value.equals(String.valueOf(node.getContentDescription()))) {
            for(AccessibilityNodeInfo current=node;current!=null;current=current.getParent())if(current.isClickable())return current.performAction(AccessibilityNodeInfo.ACTION_CLICK);
        }
        for(int i=0;i<node.getChildCount();i++)if(click(node.getChild(i),value))return true;
        return false;
    }
    private JSONObject ui() throws Exception {
        boolean okay=true;
        if(args.containsKey("click"))okay=click(getUiAutomation().getRootInActiveWindow(),args.getString("click"));
        try {
            getUiAutomation().waitForIdle(200,2000);
        }
        catch(Exception ignored) {
        }
        JSONArray rows=new JSONArray();
        nodes(getUiAutomation().getRootInActiveWindow(),rows);
        return new JSONObject().put("action_ok",okay).put("nodes",rows);
    }
    private String otp(long since) throws Exception {
        try(Cursor rows=getTargetContext().getContentResolver().query(Uri.parse("content://sms/inbox"),new String[] {
            "body"
        }
        ,"date >= ?",new String[] {
            Long.toString(since)
        }
        ,"date DESC")) {
            if(rows!=null)while(rows.moveToNext()) {
                String body=rows.getString(0);
                if(body==null||!(body.contains("红果")||body.contains("番茄"))||!body.contains("验证码"))continue;
                Matcher match=Pattern.compile("(?<![0-9])[0-9]{4,8}(?![0-9])").matcher(body);
                if(match.find()) {
                    String code=match.group();
                    if(!match.find())return code;
                }
            }
        }
        return "";
    }
    private int subscription(String phone) throws Exception {
        SubscriptionManager manager=getTargetContext().getSystemService(SubscriptionManager.class);
        List<SubscriptionInfo> all=manager.getActiveSubscriptionInfoList();
        if(all==null)throw new Exception("no_active_sim");
        int selected=Integer.parseInt(args.getString("subscription","-1"));
        for(SubscriptionInfo sim:all) {
            String number=manager.getPhoneNumber(sim.getSubscriptionId()).replace("+86","").replace(" ","");
            if(number.equals(phone)&&(selected<0||selected==sim.getSubscriptionId()))return sim.getSubscriptionId();
        }
        if(all.size()==1&&selected<0)return all.get(0).getSubscriptionId();
        for(SubscriptionInfo sim:all)if(sim.getSubscriptionId()==selected)return selected;
        throw new Exception("cannot_identify_login_sim");
    }
    private JSONObject login() throws Exception {
        initialize();
        JSONObject status=account("status",new JSONObject());
        if(status.optBoolean("loggedIn")&&!Boolean.parseBoolean(args.getString("dryRun","false")))return new JSONObject().put("loggedIn",true).put("reused_session",true);
        String phone=args.getString("phone","");
        if(!phone.matches("1[0-9]{10}"))throw new Exception("invalid_login_phone");
        getUiAutomation().adoptShellPermissionIdentity("android.permission.READ_SMS","android.permission.SEND_SMS","android.permission.READ_PHONE_STATE","android.permission.READ_PHONE_NUMBERS");
        try {
            if(Boolean.parseBoolean(args.getString("dryRun","false"))) {
                otp(System.currentTimeMillis()+60000);
                return new JSONObject().put("sms_read_access",true).put("subscription",subscription(phone)).put("sent_sms",false);
            }
            long since=System.currentTimeMillis();
            account("sendCode",new JSONObject().put("phone",phone));
            long deadline=since+120000;
            String code="";
            while(System.currentTimeMillis()<deadline&&code.isEmpty()) {
                code=otp(since);
                if(code.isEmpty())Thread.sleep(1000);
            }
            if(code.isEmpty())throw new Exception("login_otp_timeout");
            status=account("login",new JSONObject().put("code",code));
            code="";
            Set<String> sent=new HashSet<>();
            while(!status.optBoolean("loggedIn")&&status.optString("phase").equals("mfa")&&System.currentTimeMillis()<deadline) {
                String number=status.optString("smsNumber"),content=status.optString("smsContent");
                if(!number.matches("[+]?[0-9]{3,20}")||content.isEmpty()||content.length()>160)throw new Exception("invalid_official_mfa_sms");
                String challenge=number+"\n"+content;
                if(!sent.contains(challenge)) {
                    if(!sent.isEmpty())throw new Exception("mfa_challenge_changed");
                    SmsManager.getSmsManagerForSubscriptionId(subscription(phone)).sendTextMessage(number,null,content,null,null);
                    sent.add(challenge);
                }
                Thread.sleep(3000);
                status=account("verifySMS",new JSONObject());
            }
            if(!status.optBoolean("loggedIn"))throw new Exception("login_not_completed");
            return new JSONObject().put("loggedIn",true).put("mfa_messages",sent.size());
        }
        finally {
            getUiAutomation().dropShellPermissionIdentity();
        }
    }
    @Override public void onCreate(Bundle input) {
        args=input;
        start();
    }
    @Override public void onStart() {
        Bundle output=new Bundle();
        try {
            String mode=args.getString("mode","status");
            JSONObject result;
            if(mode.equals("ui"))result=ui();
            else if(mode.equals("fixture"))result=fixture(false);
            else if(mode.equals("restore"))result=fixture(true);
            else if(mode.equals("login"))result=login();
            else {
                initialize();
                JSONObject status=account("status",new JSONObject());
                result=new JSONObject().put("loggedIn",status.optBoolean("loggedIn")).put("phase",status.optString("phase"));
            }
            output.putString("summary",result.toString());
            finish(-1,output);
        }
        catch(Exception error) {
            String message=error.getMessage();
            output.putString("error",message!=null&&message.matches("[a-z_]+")?message:error.getClass().getSimpleName());
            finish(0,output);
        }
    }
}
