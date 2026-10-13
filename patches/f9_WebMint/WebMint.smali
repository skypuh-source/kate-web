.class public final Lcom/perm/kate/api/WebMint;
.super Ljava/lang/Object;
.source "WebMint.java"


# annotations
.annotation system Ldalvik/annotation/MemberClasses;
    value = {
        Lcom/perm/kate/api/WebMint$PollCb;
    }
.end annotation


# static fields
.field private static final JS_FETCH:Ljava/lang/String; = "fetch(\'https://login.vk.ru/?act=web_token\',{method:\'POST\',headers:{\'Content-Type\':\'application/x-www-form-urlencoded\'},body:\'version=5.289&app_id=7879029&access_token=\',credentials:\'include\'}).then(function(r){return r.json();}).then(function(j){window.__vkMint=(j&&j.type===\'okay\')?j.data.access_token:\'\';}).catch(function(e){window.__vkMint=\'\';});"

.field private static final TAG:Ljava/lang/String; = "Kate.Mint"

.field private static attempts:I

.field private static volatile done:Z

.field private static latch:Ljava/util/concurrent/CountDownLatch;

.field private static volatile result:Ljava/lang/String;

.field private static wv:Landroid/webkit/WebView;


# direct methods
.method public constructor <init>()V
    .locals 0

    .line 15
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method static synthetic access$000()V
    .locals 0

    .line 15
    invoke-static {}, Lcom/perm/kate/api/WebMint;->start()V

    return-void
.end method

.method static synthetic access$100(I)V
    .locals 0

    .line 15
    invoke-static {p0}, Lcom/perm/kate/api/WebMint;->schedule(I)V

    return-void
.end method

.method static synthetic access$200(Ljava/lang/String;)V
    .locals 0

    .line 15
    invoke-static {p0}, Lcom/perm/kate/api/WebMint;->finish(Ljava/lang/String;)V

    return-void
.end method

.method static synthetic access$300()Z
    .locals 1

    .line 15
    sget-boolean v0, Lcom/perm/kate/api/WebMint;->done:Z

    return v0
.end method

.method static synthetic access$400()Landroid/webkit/WebView;
    .locals 1

    .line 15
    sget-object v0, Lcom/perm/kate/api/WebMint;->wv:Landroid/webkit/WebView;

    return-object v0
.end method

.method static synthetic access$504()I
    .locals 1

    .line 15
    sget v0, Lcom/perm/kate/api/WebMint;->attempts:I

    add-int/lit8 v0, v0, 0x1

    sput v0, Lcom/perm/kate/api/WebMint;->attempts:I

    return v0
.end method

.method private static destroyAsync()V
    .locals 3

    .line 140
    sget-object v0, Lcom/perm/kate/api/WebMint;->wv:Landroid/webkit/WebView;

    const/4 v1, 0x0

    .line 141
    sput-object v1, Lcom/perm/kate/api/WebMint;->wv:Landroid/webkit/WebView;

    if-eqz v0, :cond_0

    .line 143
    new-instance v1, Landroid/os/Handler;

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;

    move-result-object v2

    invoke-direct {v1, v2}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V

    new-instance v2, Lcom/perm/kate/api/WebMint$4;

    invoke-direct {v2, v0}, Lcom/perm/kate/api/WebMint$4;-><init>(Landroid/webkit/WebView;)V

    invoke-virtual {v1, v2}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z

    :cond_0
    return-void
.end method

.method private static finish(Ljava/lang/String;)V
    .locals 1

    const/4 v0, 0x1

    .line 128
    sput-boolean v0, Lcom/perm/kate/api/WebMint;->done:Z

    .line 129
    sput-object p0, Lcom/perm/kate/api/WebMint;->result:Ljava/lang/String;

    .line 130
    invoke-static {}, Lcom/perm/kate/api/WebMint;->destroyAsync()V

    .line 131
    sget-object p0, Lcom/perm/kate/api/WebMint;->latch:Ljava/util/concurrent/CountDownLatch;

    if-eqz p0, :cond_0

    .line 132
    invoke-virtual {p0}, Ljava/util/concurrent/CountDownLatch;->countDown()V

    :cond_0
    return-void
.end method

.method public static declared-synchronized mint()Ljava/lang/String;
    .locals 5

    const-class v0, Lcom/perm/kate/api/WebMint;

    monitor-enter v0

    .line 32
    :try_start_0
    invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;

    move-result-object v1

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;

    move-result-object v2
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_1

    const/4 v3, 0x0

    if-ne v1, v2, :cond_0

    monitor-exit v0

    return-object v3

    .line 33
    :cond_0
    :try_start_1
    new-instance v1, Ljava/util/concurrent/CountDownLatch;

    const/4 v2, 0x1

    invoke-direct {v1, v2}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V

    sput-object v1, Lcom/perm/kate/api/WebMint;->latch:Ljava/util/concurrent/CountDownLatch;

    .line 34
    sput-object v3, Lcom/perm/kate/api/WebMint;->result:Ljava/lang/String;

    const/4 v1, 0x0

    .line 35
    sput-boolean v1, Lcom/perm/kate/api/WebMint;->done:Z

    .line 36
    sput v1, Lcom/perm/kate/api/WebMint;->attempts:I

    .line 37
    new-instance v1, Landroid/os/Handler;

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;

    move-result-object v2

    invoke-direct {v1, v2}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V

    new-instance v2, Lcom/perm/kate/api/WebMint$1;

    invoke-direct {v2}, Lcom/perm/kate/api/WebMint$1;-><init>()V

    invoke-virtual {v1, v2}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
    :try_end_1
    .catchall {:try_start_1 .. :try_end_1} :catchall_1

    .line 43
    :try_start_2
    sget-object v1, Lcom/perm/kate/api/WebMint;->latch:Ljava/util/concurrent/CountDownLatch;

    sget-object v2, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;

    const-wide/16 v3, 0x19

    invoke-virtual {v1, v3, v4, v2}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
    :try_end_2
    .catch Ljava/lang/InterruptedException; {:try_start_2 .. :try_end_2} :catch_0
    .catchall {:try_start_2 .. :try_end_2} :catchall_0

    .line 47
    :catch_0
    :try_start_3
    invoke-static {}, Lcom/perm/kate/api/WebMint;->release()V

    goto :goto_0

    :catchall_0
    move-exception v1

    invoke-static {}, Lcom/perm/kate/api/WebMint;->release()V

    .line 48
    throw v1

    .line 49
    :goto_0
    sget-object v1, Lcom/perm/kate/api/WebMint;->result:Ljava/lang/String;
    :try_end_3
    .catchall {:try_start_3 .. :try_end_3} :catchall_1

    monitor-exit v0

    return-object v1

    :catchall_1
    move-exception v1

    monitor-exit v0

    throw v1
.end method

.method private static release()V
    .locals 0

    .line 136
    invoke-static {}, Lcom/perm/kate/api/WebMint;->destroyAsync()V

    return-void
.end method

.method private static schedule(I)V
    .locals 5

    .line 84
    sget-boolean v0, Lcom/perm/kate/api/WebMint;->done:Z

    if-nez v0, :cond_1

    sget-object v0, Lcom/perm/kate/api/WebMint;->wv:Landroid/webkit/WebView;

    if-nez v0, :cond_0

    goto :goto_0

    .line 86
    :cond_0
    new-instance v1, Landroid/os/Handler;

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;

    move-result-object v2

    invoke-direct {v1, v2}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V

    new-instance v2, Lcom/perm/kate/api/WebMint$3;

    invoke-direct {v2, v0}, Lcom/perm/kate/api/WebMint$3;-><init>(Landroid/webkit/WebView;)V

    int-to-long v3, p0

    invoke-virtual {v1, v2, v3, v4}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z

    :cond_1
    :goto_0
    return-void
.end method

.method private static start()V
    .locals 4

    const/4 v0, 0x0

    .line 54
    :try_start_0
    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v2, 0x13

    if-ge v1, v2, :cond_0

    .line 55
    invoke-static {v0}, Lcom/perm/kate/api/WebMint;->finish(Ljava/lang/String;)V

    return-void

    .line 58
    :cond_0
    sget-object v1, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    if-nez v1, :cond_1

    .line 60
    invoke-static {v0}, Lcom/perm/kate/api/WebMint;->finish(Ljava/lang/String;)V

    return-void

    .line 63
    :cond_1
    new-instance v2, Landroid/webkit/WebView;

    invoke-direct {v2, v1}, Landroid/webkit/WebView;-><init>(Landroid/content/Context;)V

    sput-object v2, Lcom/perm/kate/api/WebMint;->wv:Landroid/webkit/WebView;

    .line 64
    invoke-virtual {v2}, Landroid/webkit/WebView;->getSettings()Landroid/webkit/WebSettings;

    move-result-object v1

    const/4 v2, 0x1

    invoke-virtual {v1, v2}, Landroid/webkit/WebSettings;->setJavaScriptEnabled(Z)V

    .line 65
    sget-object v1, Lcom/perm/kate/api/WebMint;->wv:Landroid/webkit/WebView;

    new-instance v2, Lcom/perm/kate/api/WebMint$2;

    invoke-direct {v2}, Lcom/perm/kate/api/WebMint$2;-><init>()V

    invoke-virtual {v1, v2}, Landroid/webkit/WebView;->setWebViewClient(Landroid/webkit/WebViewClient;)V

    .line 76
    sget-object v1, Lcom/perm/kate/api/WebMint;->wv:Landroid/webkit/WebView;

    const-string v2, "https://m.vk.ru/"

    invoke-virtual {v1, v2}, Landroid/webkit/WebView;->loadUrl(Ljava/lang/String;)V
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    goto :goto_0

    :catchall_0
    move-exception v1

    .line 78
    new-instance v2, Ljava/lang/StringBuilder;

    const-string v3, "webmint start: "

    invoke-direct {v2, v3}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v1

    const-string v2, "Kate.Mint"

    invoke-static {v2, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I

    .line 79
    invoke-static {v0}, Lcom/perm/kate/api/WebMint;->finish(Ljava/lang/String;)V

    :goto_0
    return-void
.end method
