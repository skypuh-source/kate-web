.class final Lcom/perm/kate/api/WebMint$PollCb;
.super Ljava/lang/Object;
.source "WebMint.java"

# interfaces
.implements Landroid/webkit/ValueCallback;


# annotations
.annotation system Ldalvik/annotation/EnclosingClass;
    value = Lcom/perm/kate/api/WebMint;
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x1a
    name = "PollCb"
.end annotation


# instance fields
.field private final v:Landroid/webkit/WebView;


# direct methods
.method constructor <init>(Landroid/webkit/WebView;)V
    .locals 0

    .line 97
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    .line 98
    iput-object p1, p0, Lcom/perm/kate/api/WebMint$PollCb;->v:Landroid/webkit/WebView;

    return-void
.end method


# virtual methods
.method public onReceiveValue(Ljava/lang/Object;)V
    .locals 3

    .line 102
    invoke-static {}, Lcom/perm/kate/api/WebMint;->access$300()Z

    move-result v0

    if-eqz v0, :cond_0

    return-void

    .line 103
    :cond_0
    check-cast p1, Ljava/lang/String;

    const/16 v0, 0x14

    if-eqz p1, :cond_1

    .line 104
    invoke-virtual {p1}, Ljava/lang/String;->length()I

    move-result v1

    const/16 v2, 0x18

    if-le v1, v2, :cond_1

    const-string v1, "\"\""

    invoke-virtual {v1, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-nez v1, :cond_1

    .line 105
    invoke-virtual {p1}, Ljava/lang/String;->length()I

    move-result v1

    const/4 v2, 0x1

    sub-int/2addr v1, v2

    invoke-virtual {p1, v2, v1}, Ljava/lang/String;->substring(II)Ljava/lang/String;

    move-result-object p1

    const-string v1, "\\\""

    const-string v2, "\""

    .line 106
    invoke-virtual {p1, v1, v2}, Ljava/lang/String;->replace(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;

    move-result-object p1

    const-string v1, "\\\\"

    const-string v2, "\\"

    .line 107
    invoke-virtual {p1, v1, v2}, Ljava/lang/String;->replace(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;

    move-result-object p1

    .line 108
    invoke-virtual {p1}, Ljava/lang/String;->length()I

    move-result v1

    if-le v1, v0, :cond_1

    .line 109
    invoke-static {p1}, Lcom/perm/kate/api/WebMint;->access$200(Ljava/lang/String;)V

    return-void

    .line 113
    :cond_1
    invoke-static {}, Lcom/perm/kate/api/WebMint;->access$504()I

    move-result p1

    if-le p1, v0, :cond_2

    const/4 p1, 0x0

    .line 114
    invoke-static {p1}, Lcom/perm/kate/api/WebMint;->access$200(Ljava/lang/String;)V

    goto :goto_0

    :cond_2
    const/16 p1, 0x190

    .line 116
    invoke-static {p1}, Lcom/perm/kate/api/WebMint;->access$100(I)V

    :goto_0
    return-void
.end method
