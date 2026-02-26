# أداة التطوير المحلي لـ Odoo

> 🌐 [English](README.md)

انقل مشروع **Odoo.sh** الخاص بك إلى بيئة Docker محلية بأمر واحد.

> جميع الإعدادات في ملف `.env` واحد — انسخه وابدأ.

---

## ⚡ البداية السريعة

```bash
# 1. الإعداد (مرة واحدة فقط)
cp .env.example .env
#    → أدخل قيم: SSH_USER, SSH_HOST, USER_REPO, USER_BRANCH

# 2. مزامنة وتشغيل
make setup

# 3. استعادة نسخة احتياطية من الإنتاج (اختياري)
make sync-db BACKUP=/path/to/backup.zip
```

Odoo متاح على → **http://localhost:8070**

---

## 🔑 ملف `.env` — الملف الوحيد الذي تعدله

| المتغير | مثال | الوصف |
|---|---|---|
| `SSH_USER` | `12345678` | معرف المستخدم الرقمي في Odoo.sh |
| `SSH_HOST` | `myproject.odoo.com` | نطاق مشروع Odoo.sh |
| `ODOO_VERSION` | `16.0` | يجب أن يطابق إصدار Odoo.sh |
| `ODOO_PORT` | `8070` | المنفذ المحلي لـ Odoo |
| `USER_REPO` | `git@github.com:org/repo.git` | مستودع الوحدات المخصصة |
| `USER_BRANCH` | `main` | الفرع المراد متابعته محلياً |
| `ADMIN_PASSWD` | `admin` | كلمة مرور Odoo الرئيسية |
| `LOCAL_DB_NAME` | `odoo` | اسم قاعدة البيانات المحلية |
| `SYNC_ODOO_CORE` | `false` | مزامنة كود Odoo الأساسي (~1.5 GB) |

---

## 🛠️ جميع الأوامر

```bash
make setup                          # مزامنة من Odoo.sh + تشغيل Docker
make sync-db BACKUP=backup.zip      # استعادة نسخة احتياطية (تمسح DB المحلية)

make up / down / stop / restart     # إدارة الحاويات
make reset-db                       # ⚠️  مسح كل البيانات + بداية جديدة

make logs                           # متابعة سجلات Odoo
make shell                          # الدخول إلى حاوية Odoo
make psql                           # فتح PostgreSQL
make update MODULE=my_module        # تحديث وحدة محددة
make open                           # فتح المتصفح

make user-status                    # حالة git للوحدات المخصصة
make user-push MSG='fix: ...'       # commit + push للوحدات المخصصة
make user-pull                      # سحب آخر التغييرات من remote

make test                           # ✅ فحص شامل للبيئة
make check-env                      # عرض الإعدادات الحالية
```

---

## 🏗️ هيكل المشروع

```
your-project/
├── .env                    ← مصدر الحقيقة الوحيد (مُدرج في .gitignore)
├── .env.example            ← القالب (انسخ هذا)
├── Makefile                ← جميع الأوامر
├── setup-odoo-local.sh     ← مزامنة + إنشاء الإعدادات + تشغيل Docker
├── sync-db.sh              ← استعادة النسخة الاحتياطية + تحييد قاعدة البيانات
└── odoo-local/             ← يُنشأ عند أول تشغيل
    ├── docker-compose.yml  ← مولَّد تلقائياً (لا تعدله)
    ├── odoo.conf           ← مولَّد تلقائياً (لا تعدله)
    ├── enterprise/         ← مزامنة من Odoo.sh، مُدرج في .gitignore
    ├── themes/             ← مزامنة من Odoo.sh، مُدرج في .gitignore
    └── user/               ← مستودع وحداتك (.git محفوظ)
```

**مستودعان، سير عمل واحد:**
- مستودع هذه الأداة ← ادفع الإعدادات والسكريبتات
- `odoo-local/user/` ← وحداتك المخصصة (`make user-push`)

---

## 🛡️ ما يفعله `sync-db` تلقائياً

يستعيد النسخة الاحتياطية ثم يحيّد قاعدة البيانات للتطوير المحلي:
- تعطيل البريد الصادر، المهام المجدولة، وبوابات الدفع
- إعادة ضبط `web.base.url` إلى `http://localhost:PORT`
- إزالة قيود انتهاء الصلاحية، مفاتيح IAP، ومفاتيح الإشعارات السحابية

---

## 🐛 وضع التطوير (مُعدَّد مسبقاً)

```ini
workers = 0        ; وحيد الخيط ← يدعم pdb والنقاط الانقطاع
log_level = debug  ; سجلات مفصلة
dev_mode = reload,xml  ; إعادة تحميل تلقائية عند تغيير الملفات
```

---

## 🔁 إعادة الاستخدام لمشروع آخر

```bash
cp setup-odoo-local.sh sync-db.sh .env.example .gitignore Makefile /new-project/
cd /new-project && cp .env.example .env
# عدّل .env ثم نفذ: make setup
```

---

## المتطلبات

`docker` + `docker compose v2` · `rsync` · `unzip` · مفتاح SSH على Odoo.sh

---

## الترخيص

MIT
