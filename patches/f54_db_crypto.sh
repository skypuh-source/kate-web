#!/bin/sh
# патч f54 (2026-11-05): прозрачное шифрование текста сообщений в локальной БД.
#
# Модель: защита копии базы/дампа/бэкапа без Keystore устройства. Не защищает от
# root-злоумышленника на разблокированном устройстве, от трафика и серверов VK,
# от превью в системной шторке.
#
# Что шифруется: messages.body, messages.title, messages.action_text.
# Что не шифруется: attachments (blob), users/chats (превью и поиск по именам),
# лента, аудио/видео-кэш. Локального SQL LIKE по body/title нет.
#
# Схема:
#   • DEK (AES-256) шифрует поля; DEK завёрнут KEK из Android Keystore
#     (alias kate_web_db, AES-GCM, setUserAuthenticationRequired(false));
#   • значение поля: "enc1:" + Base64(iv(12) + ciphertext+tag);
#   • decrypt() без префикса возвращает вход как есть (идемпотентная миграция);
#   • wrapped DEK хранится в SharedPreferences как "v1:k:" + Base64(iv+ct) —
#     версия и тип обёртки в префиксе, чтобы позже добавить PIN без перешифровки.
#
# Точки записи: DataHelper.createMessage, DataHelper.updateMessageText.
# Точки чтения: fetchMessagesThread и fetchDialogs (обёртка EncryptedCursor),
# fetchMessage и fetchMessageByCmid (явная расшифровка), doesMessageExist
# (шифрование аргумента body=?).
#
# Настройка: «Профиль» → «Шифрование базы». На API < 23 пункт скрыт, шифрование
# выключено (Keystore нет). Миграция — фоном, одной транзакцией, затем
# PRAGMA secure_delete=ON, VACUUM и wal_checkpoint(TRUNCATE), чтобы в WAL не
# оставался старый открытый текст. Ошибка расшифровки → плейсхолдер, без краша.
#
# Откат: удалить патч из patches/, пересобрать decode/ и APK; перед этим в
# приложении снять галочку «Шифровать текст сообщений» и дождаться расшифровки.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
import os

BASE = "decode/smali/com/perm/kate/"
DB = BASE + "db/"
MARK = "f54_db_crypto"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, s):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)


def ensure_class(name, body):
    path = DB + name
    if os.path.exists(path) and read(path) == body:
        print("f54 %s: уже существует" % name)
        return
    write(path, body)
    print("f54 %s: создан/обновлён" % name)


CRYPTO = '''.class public final Lcom/perm/kate/db/DbCrypto;
.super Ljava/lang/Object;
.source "DbCrypto.java"


# static fields
.field private static dek:[B

.field private static final dekLock:Ljava/lang/Object;

.field private static logged:Z


# direct methods
.method static constructor <clinit>()V
    .locals 1

    new-instance v0, Ljava/lang/Object;

    invoke-direct {v0}, Ljava/lang/Object;-><init>()V

    sput-object v0, Lcom/perm/kate/db/DbCrypto;->dekLock:Ljava/lang/Object;

    return-void
.end method

.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method private static conv(Ljava/lang/String;Z)Ljava/lang/String;
    .locals 1

    if-eqz p0, :conv_null

    if-eqz p1, :conv_dec

    invoke-static {p0}, Lcom/perm/kate/db/DbCrypto;->encrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v0

    return-object v0

    :conv_dec
    invoke-static {p0}, Lcom/perm/kate/db/DbCrypto;->decrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v0

    return-object v0

    :conv_null
    const/4 v0, 0x0

    return-object v0
.end method

.method public static decrypt(Ljava/lang/String;)Ljava/lang/String;
    .locals 9

    if-eqz p0, :d_null

    const-string v0, "enc1:"

    invoke-virtual {p0, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v0

    if-eqz v0, :d_ret

    :try_start_d
    const/4 v0, 0x5

    invoke-virtual {p0, v0}, Ljava/lang/String;->substring(I)Ljava/lang/String;

    move-result-object v0

    const/4 v1, 0x2

    invoke-static {v0, v1}, Landroid/util/Base64;->decode(Ljava/lang/String;I)[B

    move-result-object v0

    array-length v1, v0

    const/16 v2, 0xc

    if-le v1, v2, :d_fail

    sub-int/2addr v1, v2

    new-array v3, v1, [B

    const/4 v4, 0x0

    invoke-static {v0, v2, v3, v4, v1}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    const/16 v1, 0xc

    new-array v5, v1, [B

    invoke-static {v0, v4, v5, v4, v1}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->getDek()[B

    move-result-object v1

    if-eqz v1, :d_fail

    new-instance v2, Ljavax/crypto/spec/SecretKeySpec;

    const-string v4, "AES"

    invoke-direct {v2, v1, v4}, Ljavax/crypto/spec/SecretKeySpec;-><init>([BLjava/lang/String;)V

    const-string v1, "AES/GCM/NoPadding"

    invoke-static {v1}, Ljavax/crypto/Cipher;->getInstance(Ljava/lang/String;)Ljavax/crypto/Cipher;

    move-result-object v1

    const/4 v4, 0x2

    new-instance v6, Ljavax/crypto/spec/GCMParameterSpec;

    const/16 v7, 0x80

    invoke-direct {v6, v7, v5}, Ljavax/crypto/spec/GCMParameterSpec;-><init>(I[B)V

    invoke-virtual {v1, v4, v2, v6}, Ljavax/crypto/Cipher;->init(ILjava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;)V

    invoke-virtual {v1, v3}, Ljavax/crypto/Cipher;->doFinal([B)[B

    move-result-object v0

    new-instance v1, Ljava/lang/String;

    const-string v2, "UTF-8"

    invoke-direct {v1, v0, v2}, Ljava/lang/String;-><init>([BLjava/lang/String;)V
    :try_end_d
    .catch Ljava/lang/Throwable; {:try_start_d .. :try_end_d} :d_fail

    return-object v1

    :d_fail
    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->logOnce()V

    const-string v0, "[не удалось расшифровать]"

    return-object v0

    :d_null
    const/4 v0, 0x0

    return-object v0

    :d_ret
    return-object p0
.end method

.method public static encrypt(Ljava/lang/String;)Ljava/lang/String;
    .locals 7

    if-eqz p0, :e_null

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->isEnabled()Z

    move-result v0

    if-eqz v0, :e_ret

    const-string v0, "enc1:"

    invoke-virtual {p0, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v0

    if-nez v0, :e_ret

    :try_start_e
    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->getDek()[B

    move-result-object v0

    if-eqz v0, :e_ret

    new-instance v1, Ljavax/crypto/spec/SecretKeySpec;

    const-string v2, "AES"

    invoke-direct {v1, v0, v2}, Ljavax/crypto/spec/SecretKeySpec;-><init>([BLjava/lang/String;)V

    const-string v0, "AES/GCM/NoPadding"

    invoke-static {v0}, Ljavax/crypto/Cipher;->getInstance(Ljava/lang/String;)Ljavax/crypto/Cipher;

    move-result-object v0

    const/4 v2, 0x1

    invoke-virtual {v0, v2, v1}, Ljavax/crypto/Cipher;->init(ILjava/security/Key;)V

    invoke-virtual {v0}, Ljavax/crypto/Cipher;->getIV()[B

    move-result-object v1

    const-string v2, "UTF-8"

    invoke-virtual {p0, v2}, Ljava/lang/String;->getBytes(Ljava/lang/String;)[B

    move-result-object v2

    invoke-virtual {v0, v2}, Ljavax/crypto/Cipher;->doFinal([B)[B

    move-result-object v2

    array-length v3, v1

    array-length v4, v2

    add-int/2addr v3, v4

    new-array v3, v3, [B

    const/4 v5, 0x0

    array-length v6, v1

    invoke-static {v1, v5, v3, v5, v6}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    array-length v4, v2

    invoke-static {v2, v5, v3, v6, v4}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    const/4 v4, 0x2

    invoke-static {v3, v4}, Landroid/util/Base64;->encodeToString([BI)Ljava/lang/String;

    move-result-object v3

    new-instance v4, Ljava/lang/StringBuilder;

    invoke-direct {v4}, Ljava/lang/StringBuilder;-><init>()V

    const-string v5, "enc1:"

    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0
    :try_end_e
    .catch Ljava/lang/Throwable; {:try_start_e .. :try_end_e} :e_ret

    return-object v0

    :e_null
    const/4 v0, 0x0

    return-object v0

    :e_ret
    return-object p0
.end method

.method private static getDek()[B
    .locals 12

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->isSdk()Z

    move-result v0

    if-eqz v0, :gd_null

    sget-object v0, Lcom/perm/kate/db/DbCrypto;->dekLock:Ljava/lang/Object;

    monitor-enter v0

    :try_start_gd
    sget-object v1, Lcom/perm/kate/db/DbCrypto;->dek:[B

    if-nez v1, :gd_loaded

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->prefs()Landroid/content/SharedPreferences;

    move-result-object v1

    const-string v2, "kate_db_dek_v1"

    const/4 v3, 0x0

    invoke-interface {v1, v2, v3}, Landroid/content/SharedPreferences;->getString(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;

    move-result-object v2

    if-nez v2, :gd_unwrap

    const/16 v3, 0x20

    new-array v3, v3, [B

    new-instance v4, Ljava/security/SecureRandom;

    invoke-direct {v4}, Ljava/security/SecureRandom;-><init>()V

    invoke-virtual {v4, v3}, Ljava/security/SecureRandom;->nextBytes([B)V

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->getKek()Ljavax/crypto/SecretKey;

    move-result-object v4

    if-eqz v4, :gd_fail

    const-string v5, "AES/GCM/NoPadding"

    invoke-static {v5}, Ljavax/crypto/Cipher;->getInstance(Ljava/lang/String;)Ljavax/crypto/Cipher;

    move-result-object v5

    const/4 v6, 0x1

    invoke-virtual {v5, v6, v4}, Ljavax/crypto/Cipher;->init(ILjava/security/Key;)V

    invoke-virtual {v5}, Ljavax/crypto/Cipher;->getIV()[B

    move-result-object v6

    invoke-virtual {v5, v3}, Ljavax/crypto/Cipher;->doFinal([B)[B

    move-result-object v7

    array-length v8, v6

    array-length v9, v7

    add-int/2addr v8, v9

    new-array v8, v8, [B

    const/4 v11, 0x0

    array-length v10, v6

    invoke-static {v6, v11, v8, v11, v10}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    array-length v9, v7

    invoke-static {v7, v11, v8, v10, v9}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    const/4 v9, 0x2

    invoke-static {v8, v9}, Landroid/util/Base64;->encodeToString([BI)Ljava/lang/String;

    move-result-object v8

    new-instance v9, Ljava/lang/StringBuilder;

    invoke-direct {v9}, Ljava/lang/StringBuilder;-><init>()V

    const-string v10, "v1:k:"

    invoke-virtual {v9, v10}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v9, v8}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v9}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v8

    invoke-interface {v1}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;

    move-result-object v9

    const-string v10, "kate_db_dek_v1"

    invoke-interface {v9, v10, v8}, Landroid/content/SharedPreferences$Editor;->putString(Ljava/lang/String;Ljava/lang/String;)Landroid/content/SharedPreferences$Editor;

    move-result-object v8

    invoke-interface {v8}, Landroid/content/SharedPreferences$Editor;->apply()V

    sput-object v3, Lcom/perm/kate/db/DbCrypto;->dek:[B

    move-object v1, v3

    goto :gd_exit

    :gd_unwrap
    const/4 v3, 0x5

    invoke-virtual {v2, v3}, Ljava/lang/String;->substring(I)Ljava/lang/String;

    move-result-object v3

    const/4 v4, 0x2

    invoke-static {v3, v4}, Landroid/util/Base64;->decode(Ljava/lang/String;I)[B

    move-result-object v3

    array-length v4, v3

    const/16 v5, 0xc

    if-le v4, v5, :gd_fail

    sub-int/2addr v4, v5

    new-array v6, v4, [B

    const/4 v7, 0x0

    invoke-static {v3, v5, v6, v7, v4}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    const/16 v4, 0xc

    new-array v7, v4, [B

    const/4 v8, 0x0

    invoke-static {v3, v8, v7, v8, v4}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->getKek()Ljavax/crypto/SecretKey;

    move-result-object v3

    if-eqz v3, :gd_fail

    const-string v4, "AES/GCM/NoPadding"

    invoke-static {v4}, Ljavax/crypto/Cipher;->getInstance(Ljava/lang/String;)Ljavax/crypto/Cipher;

    move-result-object v4

    const/4 v8, 0x2

    new-instance v9, Ljavax/crypto/spec/GCMParameterSpec;

    const/16 v10, 0x80

    invoke-direct {v9, v10, v7}, Ljavax/crypto/spec/GCMParameterSpec;-><init>(I[B)V

    invoke-virtual {v4, v8, v3, v9}, Ljavax/crypto/Cipher;->init(ILjava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;)V

    invoke-virtual {v4, v6}, Ljavax/crypto/Cipher;->doFinal([B)[B

    move-result-object v3

    sput-object v3, Lcom/perm/kate/db/DbCrypto;->dek:[B

    move-object v1, v3

    goto :gd_exit
    :try_end_gd
    .catch Ljava/lang/Throwable; {:try_start_gd .. :try_end_gd} :gd_err

    :gd_loaded
    :gd_exit
    monitor-exit v0

    return-object v1

    :gd_err
    move-exception v1

    const-string v2, "Kate.DbCrypto"

    const-string v3, "getDek failed"

    invoke-static {v2, v3, v1}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    :gd_fail
    const/4 v1, 0x0

    goto :gd_exit

    :gd_null
    const/4 v0, 0x0

    return-object v0
.end method

.method private static getKek()Ljavax/crypto/SecretKey;
    .locals 8

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->isSdk()Z

    move-result v0

    if-eqz v0, :gk_null

    :try_start_gk
    const-string v0, "AndroidKeyStore"

    invoke-static {v0}, Ljava/security/KeyStore;->getInstance(Ljava/lang/String;)Ljava/security/KeyStore;

    move-result-object v0

    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Ljava/security/KeyStore;->load(Ljava/security/KeyStore$LoadStoreParameter;)V

    const-string v2, "kate_web_db"

    invoke-virtual {v0, v2}, Ljava/security/KeyStore;->containsAlias(Ljava/lang/String;)Z

    move-result v3

    if-nez v3, :gk_exists

    const-string v3, "AES"

    const-string v4, "AndroidKeyStore"

    invoke-static {v3, v4}, Ljavax/crypto/KeyGenerator;->getInstance(Ljava/lang/String;Ljava/lang/String;)Ljavax/crypto/KeyGenerator;

    move-result-object v3

    new-instance v4, Landroid/security/keystore/KeyGenParameterSpec$Builder;

    const/4 v5, 0x3

    invoke-direct {v4, v2, v5}, Landroid/security/keystore/KeyGenParameterSpec$Builder;-><init>(Ljava/lang/String;I)V

    const/4 v5, 0x1

    new-array v5, v5, [Ljava/lang/String;

    const/4 v6, 0x0

    const-string v7, "GCM"

    aput-object v7, v5, v6

    invoke-virtual {v4, v5}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setBlockModes([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;

    move-result-object v4

    const/4 v5, 0x1

    new-array v5, v5, [Ljava/lang/String;

    const/4 v6, 0x0

    const-string v7, "NoPadding"

    aput-object v7, v5, v6

    invoke-virtual {v4, v5}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setEncryptionPaddings([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;

    move-result-object v4

    const/4 v5, 0x0

    invoke-virtual {v4, v5}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setUserAuthenticationRequired(Z)Landroid/security/keystore/KeyGenParameterSpec$Builder;

    move-result-object v4

    invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->build()Landroid/security/keystore/KeyGenParameterSpec;

    move-result-object v4

    invoke-virtual {v3, v4}, Ljavax/crypto/KeyGenerator;->init(Ljava/security/spec/AlgorithmParameterSpec;)V

    invoke-virtual {v3}, Ljavax/crypto/KeyGenerator;->generateKey()Ljavax/crypto/SecretKey;

    :gk_exists
    invoke-virtual {v0, v2, v1}, Ljava/security/KeyStore;->getKey(Ljava/lang/String;[C)Ljava/security/Key;

    move-result-object v0

    check-cast v0, Ljavax/crypto/SecretKey;
    :try_end_gk
    .catch Ljava/lang/Throwable; {:try_start_gk .. :try_end_gk} :gk_err

    return-object v0

    :gk_err
    move-exception v0

    const-string v1, "Kate.DbCrypto"

    const-string v2, "getKek failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    :gk_null
    const/4 v0, 0x0

    return-object v0
.end method

.method public static isEnabled()Z
    .locals 3

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->isSdk()Z

    move-result v0

    if-eqz v0, :en_off

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->prefs()Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_encrypt_db"

    const/4 v2, 0x0

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z

    move-result v0

    return v0

    :en_off
    const/4 v0, 0x0

    return v0
.end method

.method private static isSdk()Z
    .locals 2

    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v1, 0x17

    if-ge v0, v1, :sdk_yes

    const/4 v0, 0x0

    return v0

    :sdk_yes
    const/4 v0, 0x1

    return v0
.end method

.method private static logOnce()V
    .locals 2

    sget-boolean v0, Lcom/perm/kate/db/DbCrypto;->logged:Z

    if-nez v0, :log_ret

    const/4 v0, 0x1

    sput-boolean v0, Lcom/perm/kate/db/DbCrypto;->logged:Z

    const-string v0, "Kate.DbCrypto"

    const-string v1, "decrypt failed"

    invoke-static {v0, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I

    :log_ret
    return-void
.end method

.method public static migrateAll(Z)V
    .locals 14

    sget-object v0, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    if-eqz v0, :mig_ret

    iget-object v0, v0, Lcom/perm/kate/db/DataHelper;->mDbHelper:Lcom/perm/kate/db/DataHelper$OpenHelper;

    if-eqz v0, :mig_ret

    invoke-virtual {v0}, Landroid/database/sqlite/SQLiteOpenHelper;->getWritableDatabase()Landroid/database/sqlite/SQLiteDatabase;

    move-result-object v0

    if-eqz v0, :mig_ret

    const-string v1, "SELECT message_id, account_id, group_id, body, title, action_text FROM messages"

    const/4 v2, 0x0

    invoke-virtual {v0, v1, v2}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;

    move-result-object v1

    invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->beginTransaction()V

    :try_start_m
    :mig_loop
    invoke-interface {v1}, Landroid/database/Cursor;->moveToNext()Z

    move-result v2

    if-eqz v2, :mig_loop_end

    const/4 v2, 0x0

    invoke-interface {v1, v2}, Landroid/database/Cursor;->getLong(I)J

    move-result-wide v2

    const/4 v4, 0x1

    invoke-interface {v1, v4}, Landroid/database/Cursor;->getLong(I)J

    move-result-wide v4

    const/4 v6, 0x2

    invoke-interface {v1, v6}, Landroid/database/Cursor;->getLong(I)J

    move-result-wide v6

    const/4 v8, 0x3

    invoke-interface {v1, v8}, Landroid/database/Cursor;->getString(I)Ljava/lang/String;

    move-result-object v8

    const/4 v9, 0x4

    invoke-interface {v1, v9}, Landroid/database/Cursor;->getString(I)Ljava/lang/String;

    move-result-object v9

    const/4 v10, 0x5

    invoke-interface {v1, v10}, Landroid/database/Cursor;->getString(I)Ljava/lang/String;

    move-result-object v10

    new-instance v11, Landroid/content/ContentValues;

    invoke-direct {v11}, Landroid/content/ContentValues;-><init>()V

    invoke-static {v8, p0}, Lcom/perm/kate/db/DbCrypto;->conv(Ljava/lang/String;Z)Ljava/lang/String;

    move-result-object v8

    const-string v12, "body"

    invoke-virtual {v11, v12, v8}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V

    invoke-static {v9, p0}, Lcom/perm/kate/db/DbCrypto;->conv(Ljava/lang/String;Z)Ljava/lang/String;

    move-result-object v9

    const-string v12, "title"

    invoke-virtual {v11, v12, v9}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V

    invoke-static {v10, p0}, Lcom/perm/kate/db/DbCrypto;->conv(Ljava/lang/String;Z)Ljava/lang/String;

    move-result-object v10

    const-string v12, "action_text"

    invoke-virtual {v11, v12, v10}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V

    const/4 v8, 0x3

    new-array v8, v8, [Ljava/lang/String;

    const/4 v9, 0x0

    invoke-static {v2, v3}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v12

    aput-object v12, v8, v9

    const/4 v9, 0x1

    invoke-static {v4, v5}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v12

    aput-object v12, v8, v9

    const/4 v9, 0x2

    invoke-static {v6, v7}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v12

    aput-object v12, v8, v9

    const-string v9, "messages"

    const-string v12, "message_id=? AND account_id=? AND group_id=?"

    invoke-virtual {v0, v9, v11, v12, v8}, Landroid/database/sqlite/SQLiteDatabase;->update(Ljava/lang/String;Landroid/content/ContentValues;Ljava/lang/String;[Ljava/lang/String;)I

    goto :mig_loop

    :mig_loop_end
    invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->setTransactionSuccessful()V
    :try_end_m
    .catch Ljava/lang/Throwable; {:try_start_m .. :try_end_m} :mig_err

    invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->endTransaction()V

    invoke-interface {v1}, Landroid/database/Cursor;->close()V

    const-string v2, "PRAGMA secure_delete=ON"

    const/4 v3, 0x0

    invoke-virtual {v0, v2, v3}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;

    move-result-object v2

    invoke-interface {v2}, Landroid/database/Cursor;->moveToFirst()Z

    invoke-interface {v2}, Landroid/database/Cursor;->close()V

    :try_start_vac
    const-string v2, "VACUUM"

    invoke-virtual {v0, v2}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    :try_end_vac
    .catch Ljava/lang/Throwable; {:try_start_vac .. :try_end_vac} :vac_err

    goto :vac_done

    :vac_err
    move-exception v2

    const-string v3, "Kate.DbCrypto"

    const-string v4, "vacuum failed"

    invoke-static {v3, v4, v2}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    :vac_done
    :try_start_wal
    const-string v2, "PRAGMA wal_checkpoint(TRUNCATE)"

    const/4 v3, 0x0

    invoke-virtual {v0, v2, v3}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;

    move-result-object v2

    invoke-interface {v2}, Landroid/database/Cursor;->moveToFirst()Z

    invoke-interface {v2}, Landroid/database/Cursor;->close()V
    :try_end_wal
    .catch Ljava/lang/Throwable; {:try_start_wal .. :try_end_wal} :wal_err

    return-void

    :wal_err
    move-exception v2

    const-string v3, "Kate.DbCrypto"

    const-string v4, "wal checkpoint failed"

    invoke-static {v3, v4, v2}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void

    :mig_err
    move-exception v2

    invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->endTransaction()V

    invoke-interface {v1}, Landroid/database/Cursor;->close()V

    throw v2

    :mig_ret
    return-void
.end method

.method private static prefs()Landroid/content/SharedPreferences;
    .locals 1

    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    return-object v0
.end method
'''

CURSOR = '''.class public Lcom/perm/kate/db/EncryptedCursor;
.super Landroid/database/CursorWrapper;
.source "EncryptedCursor.java"


# direct methods
.method public constructor <init>(Landroid/database/Cursor;)V
    .locals 0

    invoke-direct {p0, p1}, Landroid/database/CursorWrapper;-><init>(Landroid/database/Cursor;)V

    return-void
.end method


# virtual methods
.method public getString(I)Ljava/lang/String;
    .locals 3

    invoke-super {p0, p1}, Landroid/database/CursorWrapper;->getString(I)Ljava/lang/String;

    move-result-object v0

    if-eqz v0, :ec_ret

    invoke-super {p0, p1}, Landroid/database/CursorWrapper;->getColumnName(I)Ljava/lang/String;

    move-result-object v1

    if-eqz v1, :ec_ret

    const-string v2, "body"

    invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v2

    if-nez v2, :ec_decrypt

    const-string v2, "title"

    invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v2

    if-nez v2, :ec_decrypt

    const-string v2, "action_text"

    invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v2

    if-nez v2, :ec_decrypt

    :ec_ret
    return-object v0

    :ec_decrypt
    invoke-static {v0}, Lcom/perm/kate/db/DbCrypto;->decrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v0

    return-object v0
.end method
'''

MIGRATOR = '''.class public final Lcom/perm/kate/db/DbCryptoMigrator;
.super Ljava/lang/Object;
.source "DbCryptoMigrator.java"


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static start(Landroid/content/Context;Z)V
    .locals 5

    instance-of v0, p0, Landroid/app/Activity;

    if-eqz v0, :mig_ret

    check-cast p0, Landroid/app/Activity;

    new-instance v0, Landroid/app/ProgressDialog;

    invoke-direct {v0, p0}, Landroid/app/ProgressDialog;-><init>(Landroid/content/Context;)V

    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Landroid/app/ProgressDialog;->setCancelable(Z)V

    if-eqz p1, :mig_dec

    const-string v1, "Шифрование сообщений…"

    goto :mig_msg

    :mig_dec
    const-string v1, "Расшифровка сообщений…"

    :mig_msg
    invoke-virtual {v0, v1}, Landroid/app/ProgressDialog;->setMessage(Ljava/lang/CharSequence;)V

    invoke-virtual {v0}, Landroid/app/ProgressDialog;->show()V

    new-instance v1, Lcom/perm/kate/db/DbCryptoMigrator$1;

    invoke-direct {v1, p0, v0, p1}, Lcom/perm/kate/db/DbCryptoMigrator$1;-><init>(Landroid/app/Activity;Landroid/app/ProgressDialog;Z)V

    new-instance v2, Ljava/lang/Thread;

    invoke-direct {v2, v1}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V

    invoke-virtual {v2}, Ljava/lang/Thread;->start()V

    :mig_ret
    return-void
.end method
'''

MIGRATOR1 = '''.class public final Lcom/perm/kate/db/DbCryptoMigrator$1;
.super Ljava/lang/Object;
.source "DbCryptoMigrator.java"

# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field public final activity:Landroid/app/Activity;

.field public final encrypt:Z

.field public final pd:Landroid/app/ProgressDialog;


# direct methods
.method public constructor <init>(Landroid/app/Activity;Landroid/app/ProgressDialog;Z)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/perm/kate/db/DbCryptoMigrator$1;->activity:Landroid/app/Activity;

    iput-object p2, p0, Lcom/perm/kate/db/DbCryptoMigrator$1;->pd:Landroid/app/ProgressDialog;

    iput-boolean p3, p0, Lcom/perm/kate/db/DbCryptoMigrator$1;->encrypt:Z

    return-void
.end method


# virtual methods
.method public run()V
    .locals 4

    const/4 v0, 0x1

    :try_start_0
    iget-boolean v1, p0, Lcom/perm/kate/db/DbCryptoMigrator$1;->encrypt:Z

    invoke-static {v1}, Lcom/perm/kate/db/DbCrypto;->migrateAll(Z)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    goto :mig_done

    :catch_0
    move-exception v1

    const-string v2, "Kate.DbCrypto"

    const-string v3, "migrate failed"

    invoke-static {v2, v3, v1}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    const/4 v0, 0x0

    :mig_done
    new-instance v1, Lcom/perm/kate/db/DbCryptoMigrator$2;

    iget-object v2, p0, Lcom/perm/kate/db/DbCryptoMigrator$1;->activity:Landroid/app/Activity;

    iget-object v3, p0, Lcom/perm/kate/db/DbCryptoMigrator$1;->pd:Landroid/app/ProgressDialog;

    invoke-direct {v1, v2, v3, v0}, Lcom/perm/kate/db/DbCryptoMigrator$2;-><init>(Landroid/app/Activity;Landroid/app/ProgressDialog;Z)V

    iget-object v2, p0, Lcom/perm/kate/db/DbCryptoMigrator$1;->activity:Landroid/app/Activity;

    invoke-virtual {v2, v1}, Landroid/app/Activity;->runOnUiThread(Ljava/lang/Runnable;)V

    return-void
.end method
'''

MIGRATOR2 = '''.class public final Lcom/perm/kate/db/DbCryptoMigrator$2;
.super Ljava/lang/Object;
.source "DbCryptoMigrator.java"

# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field public final activity:Landroid/app/Activity;

.field public final ok:Z

.field public final pd:Landroid/app/ProgressDialog;


# direct methods
.method public constructor <init>(Landroid/app/Activity;Landroid/app/ProgressDialog;Z)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/perm/kate/db/DbCryptoMigrator$2;->activity:Landroid/app/Activity;

    iput-object p2, p0, Lcom/perm/kate/db/DbCryptoMigrator$2;->pd:Landroid/app/ProgressDialog;

    iput-boolean p3, p0, Lcom/perm/kate/db/DbCryptoMigrator$2;->ok:Z

    return-void
.end method


# virtual methods
.method public run()V
    .locals 3

    :try_start_0
    iget-object v0, p0, Lcom/perm/kate/db/DbCryptoMigrator$2;->pd:Landroid/app/ProgressDialog;

    invoke-virtual {v0}, Landroid/app/Dialog;->dismiss()V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    iget-boolean v0, p0, Lcom/perm/kate/db/DbCryptoMigrator$2;->ok:Z

    if-eqz v0, :mig_fail

    const-string v1, "Готово"

    goto :mig_show

    :mig_fail
    const-string v1, "Не удалось выполнить операцию"

    :mig_show
    iget-object v0, p0, Lcom/perm/kate/db/DbCryptoMigrator$2;->activity:Landroid/app/Activity;

    const/4 v2, 0x1

    invoke-static {v0, v1, v2}, Landroid/widget/Toast;->makeText(Landroid/content/Context;Ljava/lang/CharSequence;I)Landroid/widget/Toast;

    move-result-object v0

    invoke-virtual {v0}, Landroid/widget/Toast;->show()V

    return-void
.end method
'''

PREF_CHECK = '''.class public final Lcom/perm/kate/DbCryptoCheckBoxPreference;
.super Landroid/preference/CheckBoxPreference;
.source "DbCryptoCheckBoxPreference.java"


# direct methods
.method public constructor <init>(Landroid/content/Context;)V
    .locals 0

    invoke-direct {p0, p1}, Landroid/preference/CheckBoxPreference;-><init>(Landroid/content/Context;)V

    return-void
.end method

.method public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V
    .locals 0

    invoke-direct {p0, p1, p2}, Landroid/preference/CheckBoxPreference;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V

    return-void
.end method


# virtual methods
.method public onClick()V
    .locals 2

    invoke-super {p0}, Landroid/preference/TwoStatePreference;->onClick()V

    invoke-virtual {p0}, Landroid/preference/TwoStatePreference;->isChecked()Z

    move-result v0

    invoke-virtual {p0}, Landroid/preference/Preference;->getContext()Landroid/content/Context;

    move-result-object v1

    invoke-static {v1, v0}, Lcom/perm/kate/db/DbCryptoMigrator;->start(Landroid/content/Context;Z)V

    return-void
.end method

.method protected onAttachedToHierarchy(Landroid/preference/PreferenceManager;)V
    .locals 2

    invoke-super {p0, p1}, Landroid/preference/Preference;->onAttachedToHierarchy(Landroid/preference/PreferenceManager;)V

    # f54_db_crypto: на API < 23 Keystore нет — скрываем весь экран
    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v1, 0x17

    if-ge v0, v1, :att_ret

    invoke-virtual {p0}, Landroid/preference/Preference;->getParent()Landroid/preference/PreferenceGroup;

    move-result-object v0

    if-eqz v0, :att_ret

    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Landroid/preference/Preference;->setVisible(Z)V

    :att_ret
    return-void
.end method
'''

PREF_APPLY = '''.class public final Lcom/perm/kate/DbCryptoApplyPreference;
.super Landroid/preference/Preference;
.source "DbCryptoApplyPreference.java"


# direct methods
.method public constructor <init>(Landroid/content/Context;)V
    .locals 0

    invoke-direct {p0, p1}, Landroid/preference/Preference;-><init>(Landroid/content/Context;)V

    return-void
.end method

.method public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V
    .locals 0

    invoke-direct {p0, p1, p2}, Landroid/preference/Preference;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V

    return-void
.end method


# virtual methods
.method public onClick()V
    .locals 2

    invoke-static {}, Lcom/perm/kate/db/DbCrypto;->isEnabled()Z

    move-result v0

    invoke-virtual {p0}, Landroid/preference/Preference;->getContext()Landroid/content/Context;

    move-result-object v1

    invoke-static {v1, v0}, Lcom/perm/kate/db/DbCryptoMigrator;->start(Landroid/content/Context;Z)V

    return-void
.end method
'''

ensure_class("DbCrypto.smali", CRYPTO)
ensure_class("EncryptedCursor.smali", CURSOR)
ensure_class("DbCryptoMigrator.smali", MIGRATOR)
ensure_class("DbCryptoMigrator$1.smali", MIGRATOR1)
ensure_class("DbCryptoMigrator$2.smali", MIGRATOR2)
ensure_class("../DbCryptoCheckBoxPreference.smali", PREF_CHECK)
ensure_class("../DbCryptoApplyPreference.smali", PREF_APPLY)

# --- DataHelper ---------------------------------------------------------------
p = DB + "DataHelper.smali"
s = read(p)

if MARK in s:
    print("f54 DataHelper: уже применён")
else:
    def sub(a, b):
        global s
        assert s.count(a) == 1, "f54: якорь не найден/не уникален: %r" % a[:80]
        s = s.replace(a, b, 1)

    # createMessage: title
    sub(
        '''    .line 3493
    const-string p2, "title"

    iget-object p3, p1, Lcom/perm/kate/api/Message;->title:Ljava/lang/String;

    invoke-virtual {v0, p2, p3}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V''',
        '''    .line 3493
    const-string p2, "title"

    iget-object p3, p1, Lcom/perm/kate/api/Message;->title:Ljava/lang/String;

    invoke-static {p3}, Lcom/perm/kate/db/DbCrypto;->encrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p3

    invoke-virtual {v0, p2, p3}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V''')

    # createMessage: body
    sub(
        '''    .line 3494
    const-string p2, "body"

    iget-object p3, p1, Lcom/perm/kate/api/Message;->body:Ljava/lang/String;

    invoke-virtual {v0, p2, p3}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V''',
        '''    .line 3494
    const-string p2, "body"

    iget-object p3, p1, Lcom/perm/kate/api/Message;->body:Ljava/lang/String;

    invoke-static {p3}, Lcom/perm/kate/db/DbCrypto;->encrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p3

    invoke-virtual {v0, p2, p3}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V''')

    # createMessage: action_text
    sub(
        '''    .line 3507
    const-string p3, "action_text"

    invoke-virtual {v0, p3, p2}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V''',
        '''    .line 3507
    const-string p3, "action_text"

    invoke-static {p2}, Lcom/perm/kate/db/DbCrypto;->encrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p2

    invoke-virtual {v0, p3, p2}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V''')

    # updateMessageText: body
    sub(
        '''    .line 3549
    const-string v1, "body"

    invoke-virtual {v0, v1, p7}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V''',
        '''    .line 3549
    const-string v1, "body"

    invoke-static {p7}, Lcom/perm/kate/db/DbCrypto;->encrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p7

    invoke-virtual {v0, v1, p7}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V''')

    # fetchMessage: body
    sub(
        '''    .line 3910
    invoke-interface {p5, v4}, Landroid/database/Cursor;->getString(I)Ljava/lang/String;

    move-result-object p3

    iput-object p3, v0, Lcom/perm/kate/api/Message;->body:Ljava/lang/String;''',
        '''    .line 3910
    invoke-interface {p5, v4}, Landroid/database/Cursor;->getString(I)Ljava/lang/String;

    move-result-object p3

    invoke-static {p3}, Lcom/perm/kate/db/DbCrypto;->decrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p3

    iput-object p3, v0, Lcom/perm/kate/api/Message;->body:Ljava/lang/String;''')

    # fetchMessageByCmid: body
    sub(
        '''    .line 3934
    invoke-interface {p6, p2}, Landroid/database/Cursor;->getString(I)Ljava/lang/String;

    move-result-object p2

    iput-object p2, v0, Lcom/perm/kate/api/Message;->body:Ljava/lang/String;''',
        '''    .line 3934
    invoke-interface {p6, p2}, Landroid/database/Cursor;->getString(I)Ljava/lang/String;

    move-result-object p2

    invoke-static {p2}, Lcom/perm/kate/db/DbCrypto;->decrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p2

    iput-object p2, v0, Lcom/perm/kate/api/Message;->body:Ljava/lang/String;''')

    # doesMessageExist: encrypt argument
    sub(
        '''    .line 3879
    invoke-static {p4, p5}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object p4

    invoke-static {p1, p2}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object p1''',
        '''    invoke-static {p3}, Lcom/perm/kate/db/DbCrypto;->encrypt(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p3

    .line 3879
    invoke-static {p4, p5}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object p4

    invoke-static {p1, p2}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object p1''')

    # fetchMessagesThread: wrap cursor
    sub(
        '''    .line 3822
    invoke-virtual {p2, p1, p4}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;

    move-result-object p1

    return-object p1''',
        '''    .line 3822
    invoke-virtual {p2, p1, p4}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;

    move-result-object p1

    new-instance p2, Lcom/perm/kate/db/EncryptedCursor;

    invoke-direct {p2, p1}, Lcom/perm/kate/db/EncryptedCursor;-><init>(Landroid/database/Cursor;)V

    return-object p2''')

    # fetchDialogs: wrap cursor
    sub(
        '''    invoke-virtual {p6, p5, p3}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;

    move-result-object p1

    return-object p1''',
        '''    invoke-virtual {p6, p5, p3}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;

    move-result-object p1

    new-instance v0, Lcom/perm/kate/db/EncryptedCursor;

    invoke-direct {v0, p1}, Lcom/perm/kate/db/EncryptedCursor;-><init>(Landroid/database/Cursor;)V

    return-object v0''')

    s += "\n# f54_db_crypto\n"
    write(p, s)
    print("f54 DataHelper: правки внесены")

# --- preferences.xml ----------------------------------------------------------
anchor = '        <PreferenceScreen android:title="@string/privacy_settings" android:key="key_privacy_settings" />\n'
item = '''        <PreferenceScreen android:title="Шифрование базы" android:key="key_db_crypto" android:summary="Текст сообщений в локальной базе">
            <com.perm.kate.DbCryptoCheckBoxPreference android:title="Шифровать текст сообщений" android:key="key_encrypt_db" android:summary="AES-GCM; ключ хранится в Android Keystore. При потере ключа история нечитаема." android:defaultValue="false" />
            <com.perm.kate.DbCryptoApplyPreference android:title="Применить к существующим сообщениям" android:summary="Зашифровать или расшифровать уже сохранённые сообщения" />
        </PreferenceScreen>
'''
for p in ("decode/res/xml/preferences.xml", "decode/res/xml-v22/preferences.xml"):
    if not os.path.exists(p):
        continue
    s = read(p)
    if "key_db_crypto" in s:
        print("f54 %s: уже применён" % p)
        continue
    assert s.count(anchor) == 1, "f54: якорь privacy_settings не найден в %s" % p
    s = s.replace(anchor, anchor + item, 1)
    write(p, s)
    print("f54 %s: пункт добавлен" % p)
PYEOF
