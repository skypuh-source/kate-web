.class public Lcom/perm/kate/api/RedesignNotifications;
.super Ljava/lang/Object;
.source "RedesignNotifications.java"


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static convert(Lorg/json/JSONObject;)Lcom/perm/kate/api/Notifications;
    .locals 12

    new-instance v0, Lcom/perm/kate/api/Notifications;

    invoke-direct {v0}, Lcom/perm/kate/api/Notifications;-><init>()V

    const-string v1, "users"

    invoke-virtual {p0, v1}, Lorg/json/JSONObject;->optJSONArray(Ljava/lang/String;)Lorg/json/JSONArray;

    move-result-object v1

    if-eqz v1, :cond_users

    const/4 v2, 0x1

    invoke-static {v1, v2}, Lcom/perm/kate/api/User;->parseUsers(Lorg/json/JSONArray;Z)Ljava/util/ArrayList;

    move-result-object v1

    iput-object v1, v0, Lcom/perm/kate/api/Notifications;->profiles:Ljava/util/ArrayList;

    :cond_users
    const-string v1, "groups"

    invoke-virtual {p0, v1}, Lorg/json/JSONObject;->optJSONArray(Ljava/lang/String;)Lorg/json/JSONArray;

    move-result-object v1

    if-eqz v1, :cond_groups

    invoke-static {v1}, Lcom/perm/kate/api/Group;->parseGroups(Lorg/json/JSONArray;)Ljava/util/ArrayList;

    move-result-object v1

    iput-object v1, v0, Lcom/perm/kate/api/Notifications;->groups:Ljava/util/ArrayList;

    :cond_groups
    iget-object v1, v0, Lcom/perm/kate/api/Notifications;->notifications:Ljava/util/ArrayList;

    const-string v2, "notifications"

    invoke-virtual {p0, v2}, Lorg/json/JSONObject;->optJSONArray(Ljava/lang/String;)Lorg/json/JSONArray;

    move-result-object v2

    if-eqz v2, :cond_done

    const/4 v3, 0x0

    :goto_loop
    invoke-virtual {v2}, Lorg/json/JSONArray;->length()I

    move-result v4

    if-ge v3, v4, :cond_done

    invoke-virtual {v2, v3}, Lorg/json/JSONArray;->optJSONObject(I)Lorg/json/JSONObject;

    move-result-object v4

    if-eqz v4, :goto_next

    new-instance v5, Lcom/perm/kate/api/Notification;

    invoke-direct {v5}, Lcom/perm/kate/api/Notification;-><init>()V

    const-string v6, "date"

    invoke-virtual {v4, v6}, Lorg/json/JSONObject;->optLong(Ljava/lang/String;)J

    move-result-wide v6

    invoke-static {v6, v7}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v6

    iput-object v6, v5, Lcom/perm/kate/api/Notification;->date:Ljava/lang/Long;

    const-string v6, "reply_comment"

    iput-object v6, v5, Lcom/perm/kate/api/Notification;->type:Ljava/lang/String;

    new-instance v6, Lcom/perm/kate/api/Comment;

    invoke-direct {v6}, Lcom/perm/kate/api/Comment;-><init>()V

    const/4 v8, 0x0

    const-string v7, "attachment"

    invoke-virtual {v4, v7}, Lorg/json/JSONObject;->optJSONObject(Ljava/lang/String;)Lorg/json/JSONObject;

    move-result-object v7

    if-eqz v7, :cond_att

    const-string v9, "main_text"

    invoke-virtual {v7, v9}, Lorg/json/JSONObject;->optString(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v8

    :cond_att
    if-eqz v8, :cond_tex

    invoke-virtual {v8}, Ljava/lang/String;->length()I

    move-result v9

    if-nez v9, :cond_have

    :cond_tex
    const-string v8, "text"

    invoke-virtual {v4, v8}, Lorg/json/JSONObject;->optString(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v8

    :cond_have
    iput-object v8, v6, Lcom/perm/kate/api/Comment;->message:Ljava/lang/String;

    const-string v7, "image"

    invoke-virtual {v4, v7}, Lorg/json/JSONObject;->optJSONObject(Ljava/lang/String;)Lorg/json/JSONObject;

    move-result-object v7

    if-eqz v7, :cond_img

    const-string v9, "owner"

    invoke-virtual {v7, v9}, Lorg/json/JSONObject;->optJSONObject(Ljava/lang/String;)Lorg/json/JSONObject;

    move-result-object v7

    if-eqz v7, :cond_img

    const-string v9, "id"

    invoke-virtual {v7, v9}, Lorg/json/JSONObject;->optLong(Ljava/lang/String;)J

    move-result-wide v10

    const-string v9, "type"

    invoke-virtual {v7, v9}, Lorg/json/JSONObject;->optString(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v9

    const-string v7, "group"

    invoke-virtual {v9, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v7

    if-eqz v7, :cond_sign

    neg-long v10, v10

    :cond_sign
    iput-wide v10, v6, Lcom/perm/kate/api/Comment;->from_id:J

    :cond_img
    iput-object v6, v5, Lcom/perm/kate/api/Notification;->feedback:Ljava/lang/Object;

    new-instance v6, Lcom/perm/kate/api/Comment;

    invoke-direct {v6}, Lcom/perm/kate/api/Comment;-><init>()V

    const-string v7, ""

    iput-object v7, v6, Lcom/perm/kate/api/Comment;->message:Ljava/lang/String;

    iput-object v6, v5, Lcom/perm/kate/api/Notification;->parent:Ljava/lang/Object;

    invoke-virtual {v1, v5}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    :goto_next
    add-int/lit8 v3, v3, 0x1

    goto :goto_loop

    :cond_done
    return-object v0
.end method
