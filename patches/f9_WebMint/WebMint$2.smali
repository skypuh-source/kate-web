.class Lcom/perm/kate/api/WebMint$2;
.super Landroid/webkit/WebViewClient;
.source "WebMint.java"


# annotations
.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lcom/perm/kate/api/WebMint;->start()V
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation


# direct methods
.method constructor <init>()V
    .locals 0

    .line 63
    invoke-direct {p0}, Landroid/webkit/WebViewClient;-><init>()V

    return-void
.end method


# virtual methods
.method public onPageFinished(Landroid/webkit/WebView;Ljava/lang/String;)V
    .locals 1

    const/4 p2, 0x0

    :try_start_0
    const-string v0, "fetch(\'https://login.vk.ru/?act=web_token\',{method:\'POST\',headers:{\'Content-Type\':\'application/x-www-form-urlencoded\'},body:\'version=5.289&app_id=7879029&access_token=\',credentials:\'include\'}).then(function(r){return r.json();}).then(function(j){window.__vkMint=(j&&j.type===\'okay\')?j.data.access_token:\'\';}).catch(function(e){window.__vkMint=\'\';});"

    .line 66
    invoke-virtual {p1, v0, p2}, Landroid/webkit/WebView;->evaluateJavascript(Ljava/lang/String;Landroid/webkit/ValueCallback;)V

    const/16 p1, 0x258

    .line 67
    invoke-static {p1}, Lcom/perm/kate/api/WebMint;->access$100(I)V
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    goto :goto_0

    .line 69
    :catchall_0
    invoke-static {p2}, Lcom/perm/kate/api/WebMint;->access$200(Ljava/lang/String;)V

    :goto_0
    return-void
.end method
