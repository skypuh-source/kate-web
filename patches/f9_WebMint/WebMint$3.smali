.class Lcom/perm/kate/api/WebMint$3;
.super Ljava/lang/Object;
.source "WebMint.java"

# interfaces
.implements Ljava/lang/Runnable;


# annotations
.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lcom/perm/kate/api/WebMint;->schedule(I)V
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation


# instance fields
.field final synthetic val$v:Landroid/webkit/WebView;


# direct methods
.method constructor <init>(Landroid/webkit/WebView;)V
    .locals 0
    .annotation system Ldalvik/annotation/Signature;
        value = {
            "()V"
        }
    .end annotation

    .line 82
    iput-object p1, p0, Lcom/perm/kate/api/WebMint$3;->val$v:Landroid/webkit/WebView;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method


# virtual methods
.method public run()V
    .locals 3

    .line 84
    invoke-static {}, Lcom/perm/kate/api/WebMint;->access$300()Z

    move-result v0

    if-nez v0, :cond_1

    iget-object v0, p0, Lcom/perm/kate/api/WebMint$3;->val$v:Landroid/webkit/WebView;

    invoke-static {}, Lcom/perm/kate/api/WebMint;->access$400()Landroid/webkit/WebView;

    move-result-object v1

    if-eq v0, v1, :cond_0

    goto :goto_0

    .line 86
    :cond_0
    :try_start_0
    iget-object v0, p0, Lcom/perm/kate/api/WebMint$3;->val$v:Landroid/webkit/WebView;

    const-string v1, "window.__vkMint||\'\'"

    new-instance v2, Lcom/perm/kate/api/WebMint$PollCb;

    invoke-direct {v2, v0}, Lcom/perm/kate/api/WebMint$PollCb;-><init>(Landroid/webkit/WebView;)V

    invoke-virtual {v0, v1, v2}, Landroid/webkit/WebView;->evaluateJavascript(Ljava/lang/String;Landroid/webkit/ValueCallback;)V
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    goto :goto_0

    :catchall_0
    const/4 v0, 0x0

    .line 88
    invoke-static {v0}, Lcom/perm/kate/api/WebMint;->access$200(Ljava/lang/String;)V

    :cond_1
    :goto_0
    return-void
.end method
