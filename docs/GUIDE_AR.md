# دليل المشروع بالعربي — شرح خطوة بخطوة

> هذا الملف للدراسة والمناقشة. التسليم الرسمي هو ملف `README.md` (بالإنجليزية) مع الـ repo.

## 0) الفكرة العامة

بدلاً من أن تضغط على أزرار AWS وتدخل على السيرفرات يدوياً، نكتب **كوداً** يفعل كل شيء:

```
GitHub repo → deploy.sh → Terraform → AWS resources → gen_inventory.py → Ansible → Linux setup → Docker Compose → Health check
                                                                                              ↘ backup.sh + cron → S3
```

كل أداة لها مهمة واحدة فقط، وتسلّم النتيجة للأداة التالية:

| الأداة | مهمتها | بماذا تسلّم؟ |
|---|---|---|
| Terraform | إنشاء البنية التحتية (السيرفرات والشبكة والتخزين) | عناوين IP واسم الـ bucket |
| Python | تحويل ناتج Terraform إلى ملف Inventory | ملف `hosts.ini` |
| Ansible | إعداد السيرفرات من الداخل | سيرفرات جاهزة + Docker |
| Docker Compose | تشغيل التطبيق في حاويات | Flask+Nginx و Postgres يعملون |
| Bash | فحص الصحة + نسخ احتياطي + حذف | تأكيد أن كل شيء سليم |

---

## 1) Terraform — «ابنِ لي البنية التحتية»

**الملفات:** `terraform/main.tf` و `variables.tf` و `outputs.tf` و `versions.tf`

**الفائدة:** البنية موصوفة في ملفات نصية (Infrastructure as Code): قابلة للتكرار والمراجعة، وتُحذف بأمر واحد.

**ماذا ينشئ؟**

| المورد | وظيفته |
|---|---|
| `aws_vpc` | شبكة خاصة بك معزولة داخل AWS (`10.0.0.0/16`) |
| `aws_subnet` + `aws_internet_gateway` + `aws_route_table` | شبكة فرعية عامة + باب للإنترنت + جدول توجيه لها |
| `aws_security_group` (web) | يسمح بـ HTTP (80) من الجميع، و SSH (22) من **IP جهازك فقط** |
| `aws_security_group` (db) | يسمح بـ Postgres (5432) **من سيرفر الويب فقط**، و SSH من IP جهازك |
| `aws_instance` ×2 | سيرفر **web** وسيرفر **db** (Ubuntu 22.04، نوع t3.micro) |
| `aws_key_pair` | المفتاح **العام** فقط لتسجيل الدخول (المفتاح الخاص يبقى عندك) |
| `aws_s3_bucket` | مخزن النسخ الاحتياطية (مشفّر، ممنوع الوصول العام، يحذف النسخ القديمة بعد 30 يوماً) |
| `aws_iam_role` | يعطي سيرفر الـ db صلاحية الكتابة على الـ bucket **بدون مفاتيح** |
| `outputs.tf` | يطبع IPs واسم الـ bucket ليقرأها Python |

**لماذا IAM Role وليس Access Keys؟** لأن المفاتيح المكتوبة على السيرفر قد تُسرق. الـ Role يعطي صلاحيات مؤقتة تلقائياً — وهذا شرط «بدون secrets في الكود».

---

## 2) Python — «حوّل ناتج Terraform إلى Inventory»

**الملف:** `scripts/gen_inventory.py`

**المشكلة:** Ansible يحتاج أن يعرف **أين** السيرفرات (عناوين IP)، وهذه العناوين تتغير في كل deploy.

**الحل:** السكريبت يشغّل `terraform output -json` ويكتب `ansible/inventory/hosts.ini` تلقائياً:

```ini
[web]
web-server ansible_host=3.x.x.x private_ip=10.0.1.10
[db]
db-server  ansible_host=3.x.x.y private_ip=10.0.1.20
[all:vars]
ansible_user=ubuntu
s3_bucket=...
```

- يتحقق أن المخرجات موجودة وأن الـ IPs صحيحة قبل الكتابة.
- يستخدم مكتبة Python القياسية فقط (لا يحتاج تثبيت شيء).
- له اختبارات في `tests/test_gen_inventory.py`.

---

## 3) Ansible (Roles + Vault) — «جهّز السيرفرات من الداخل»

**الملفات:** `ansible/site.yml` و `ansible/roles/*`

**الفائدة:** تضبط السيرفرات كلها بنفس الطريقة وبدون دخول يدوي، وتستطيع تكرارها آلاف المرات.

**الـ Roles (كل role مسؤول عن مهمة واحدة):**

| Role | يعمل على | ماذا يفعل؟ |
|---|---|---|
| `common` | الاثنين | تثبيت حزم أساسية، **تقوية SSH** (منع root وكلمات السر)، fail2ban، جدار ufw |
| `docker` | الاثنين | إضافة مستودع Docker الرسمي وتثبيت Docker + Compose plugin |
| `db` | db | تشغيل Postgres بـ Docker Compose + كتابة ملف `.env` بكلمة السر |
| `backup` | db | تثبيت AWS CLI، وضع سكريبت النسخ الاحتياطي، وجدولته بـ cron |
| `web` | web | نسخ كود Flask و Nginx، تشغيلهم بـ Compose، واختبار `/health` |

**Ansible Vault:** كلمة سر Postgres تُولَّد عشوائياً في أول deploy وتُخزَّن **مشفّرة** في `ansible/group_vars/all/vault.yml`. كلمة سر الـ Vault في `.vault_pass`. الملفان داخل `.gitignore` فلا يصعدان إلى GitHub.

**Idempotent يعني ماذا؟** إذا شغّلت Ansible مرة ثانية على سيرفر جاهز، لا يغيّر شيئاً (`changed=0`). السبب: نستخدم modules تصف **الحالة المطلوبة** (`state: present`) وليس أوامر تنفَّذ كل مرة، وإعادة التشغيل تتم عبر **handlers** فقط عندما يتغير ملف فعلاً. للتحقق: `./scripts/check_idempotency.sh`.

---

## 4) Docker Compose — «شغّل التطبيق»

**على web** (`ansible/roles/web/templates/docker-compose.yml.j2`):
- **Flask** (`app/flask/app.py`) خلف gunicorn: صفحة رئيسية تزيد عدّاداً مخزّناً في Postgres، و `/health`.
- **Nginx** يستقبل على المنفذ 80 ويمرّر الطلبات إلى Flask (Reverse Proxy). الفائدة: Nginx أسرع في الاستقبال، ويخفي Flask عن الإنترنت.

**على db:** حاوية **Postgres 16** مع volume دائم (`pgdata`) حتى لا تضيع البيانات إذا أُعيد تشغيل الحاوية، و healthcheck بـ `pg_isready`.

**كيف يتصل web بـ db؟** عبر الـ **Private IP** داخل الـ VPC (وليس الإنترنت)، ويُكتب في `.env` من الـ inventory.

---

## 5) Bash — فحص الصحة + النسخ الاحتياطي

**`scripts/health_check.sh`:** يطلب `http://<web_ip>/health` كل 5 ثوانٍ (حتى 30 مرة) حتى يحصل على **HTTP 200**، وإلا يفشل. في تطبيقنا `/health` يرجع 200 **فقط إذا كان Flask يستطيع الوصول إلى Postgres** — أي أن الفحص يختبر السلسلة كلها.

**`db-backup.sh`** (قالب في `roles/backup/templates`) يعمل على سيرفر db:
1. `pg_dump` لقاعدة البيانات من داخل الحاوية.
2. ضغطها في `db-backup-<التاريخ>.tar.gz`.
3. رفعها إلى `s3://<bucket>/backups/` (بصلاحيات الـ IAM Role).
4. حذف النسخ المحلية الأقدم من 7 أيام. وقفل `flock` يمنع تشغيل نسختين معاً.

**cron:** يشغّله يومياً الساعة 02:00 (في crontab الخاص بـ root عبر module `cron`). وفي نهاية `deploy.sh` يُشغَّل مرة واحدة للتأكد أنه يعمل فعلاً.

---

## 6) `./destroy.sh` — «احذف كل شيء»

يشغّل `terraform destroy` فيحذف السيرفرات والشبكة والـ bucket (حتى لو فيه نسخ، بسبب `force_destroy`) والـ IAM. يسألك تأكيداً (`yes`)، أو استخدم `--yes`. و`--purge` يحذف أيضاً المفتاح وملفات Vault المحلية.

> ⚠️ **افعل هذا بعد كل جلسة** حتى لا تُحاسَب على الـ Public IPv4 والسيرفرات.

---

## 7) ما الذي يفعله `./deploy.sh` بالترتيب؟

1. فحص الأدوات وبيانات دخول AWS.
2. توليد مفتاح SSH (في `.state/`).
3. توليد Vault (كلمة سر عشوائية + تشفير).
4. Terraform init + apply (مع تحديد IP جهازك تلقائياً لـ SSH).
5. Python: توليد الـ inventory.
6. Ansible: إعداد السيرفرات وتشغيل الحاويات.
7. Health check.
8. تشغيل backup مرة واحدة والتحقق من S3.

يمكن إعادة تشغيله بأمان؛ كل خطوة تتجاهل ما هو موجود.

---

## 8) تشغيل المشروع على Ubuntu

**أ) انقل الملف إلى Ubuntu** (اختر واحدة):
- حمّل `aws-automated-deployment.zip` مباشرة على جهاز Ubuntu.
- من Windows: `scp aws-automated-deployment.zip USER@UBUNTU_IP:~/`
- أو فلاش USB. (الأفضل بعد رفعه على GitHub: `git clone`.)

**ب) فك الضغط وتثبيت الأدوات:**
```bash
sudo apt update && sudo apt install -y unzip
unzip aws-automated-deployment.zip
cd aws-automated-deployment
chmod +x deploy.sh destroy.sh scripts/*.sh scripts/gen_inventory.py
./scripts/setup_ubuntu.sh     # يثبّت Terraform و AWS CLI و Ansible
```

**ج) بيانات AWS:**
```bash
aws configure
# AWS Access Key ID:     (من IAM User)
# AWS Secret Access Key: (من IAM User)
# Default region name:   eu-central-1
aws sts get-caller-identity   # للتأكد أنها تعمل
```
> أنشئ IAM User مخصصاً للمشروع (وليس الـ root)، ولا تضع مفاتيحه في أي ملف داخل المشروع.

**د) التشغيل:**
```bash
./deploy.sh
./scripts/check_idempotency.sh
./destroy.sh
```

---

## 9) رفع المشروع على GitHub (3 branches + Pull Requests)

**المتطلب:** 3 branches على الأقل + Pull Requests. الخطة: `main` للمستقر، وثلاثة فروع ميزات تُدمج عبر PR.

**تهيئة (مرة واحدة):**
```bash
git config --global user.name  "Ammar"
git config --global user.email "your-email@example.com"
sudo apt install -y gh && gh auth login        # تسجيل الدخول لـ GitHub
```

**1) أنشئ المستودع وارفع `main`:**
```bash
cd aws-automated-deployment
git init -b main
git add README.md .gitignore docs
git commit -m "docs: add README, architecture diagram and study guide"
gh repo create aws-automated-deployment --public --source=. --remote=origin
git push -u origin main
```

**2) كرّر هذه الدورة لكل فرع من الثلاثة:**

الفرع الأول — Terraform:
```bash
git checkout -b feature/terraform
git add terraform
git commit -m "feat(terraform): VPC, 2 EC2, S3 bucket, IAM role"
git push -u origin feature/terraform
gh pr create --base main --head feature/terraform \
  --title "Add Terraform infrastructure" --body "VPC + web/db EC2 + S3 + IAM role + security groups"
gh pr merge feature/terraform --merge
git checkout main && git pull
```

الفرع الثاني — Ansible:
```bash
git checkout -b feature/ansible
git add ansible
git commit -m "feat(ansible): roles common, docker, db, backup, web + vault"
git push -u origin feature/ansible
gh pr create --base main --head feature/ansible \
  --title "Add Ansible roles" --body "Hardening, Docker, Postgres, Flask+Nginx, backup cron"
gh pr merge feature/ansible --merge
git checkout main && git pull
```

الفرع الثالث — التطبيق والسكريبتات:
```bash
git checkout -b feature/app-and-scripts
git add app scripts tests deploy.sh destroy.sh
git commit -m "feat: Flask app, deploy/destroy scripts, inventory generator, tests"
git push -u origin feature/app-and-scripts
gh pr create --base main --head feature/app-and-scripts \
  --title "Add app and automation scripts" --body "deploy.sh, destroy.sh, gen_inventory.py, health check, tests"
gh pr merge feature/app-and-scripts --merge
git checkout main && git pull
```

> بدون `gh`: ادفع الفرع ثم افتح GitHub ← زر **Compare & pull request** ← **Merge pull request**.

**قبل كل `git add`/`commit` تأكد أنه لا توجد أسرار:**
```bash
git status                       # لا يجب أن يظهر .state أو .vault_pass أو vault.yml أو tfstate
git ls-files | grep -Ei "vault_pass|vault.yml$|tfstate|id_ed25519|\.pem" || echo "clean"
```

بعد أول `./deploy.sh` ناجح يظهر `terraform/.terraform.lock.hcl` — ارفعه في commit صغير (فرع رابع أو على أحد الفروع)، فهو يثبّت نسخ الـ providers.

---

## 10) قائمة التحقق من متطلبات التسليم

| المتطلب | أين؟ |
|---|---|
| GitHub repo (3 branches + PRs) | القسم 9 |
| Deploy بأمر واحد | `./deploy.sh` |
| Terraform: VPC + 2 EC2 + S3 | `terraform/main.tf` |
| Python: inventory من outputs | `scripts/gen_inventory.py` |
| Ansible Roles + Vault | `ansible/roles/*`، `group_vars/all/vault.yml` |
| Docker Compose: Flask+Nginx على web و Postgres على db | قوالب `docker-compose.yml.j2` |
| Bash: health check + backup بـ cron إلى S3 | `scripts/health_check.sh` و `roles/backup` |
| `./destroy.sh` | موجود |
| Ansible idempotent (changed=0) | `./scripts/check_idempotency.sh` |
| لا secrets في الكود | `.gitignore` + Vault + IAM Role |
| README + صورة architecture | `README.md` و `docs/architecture.jpg` |
| بدون CI/CD | لا يوجد |

---

## 11) أسئلة قد يسألها المدرّب

- **لماذا وضعت DB في subnet عامة؟** لتجنّب تكلفة NAT Gateway ضمن الـ Free Tier. الحماية بالـ Security Group: المنفذ 5432 مفتوح فقط من الـ SG الخاص بالويب. في الإنتاج: subnet خاصة + NAT/Bastion.
- **ماذا يحدث لو شغّلت `deploy.sh` مرتين؟** Terraform لا يغيّر شيئاً، و Ansible يعطي `changed=0`.
- **أين الأسرار؟** كلمة سر DB في Ansible Vault (مشفّرة وخارج Git)، مفتاح SSH في `.state/`، وصلاحيات S3 عبر IAM Role.
- **لماذا Nginx أمام Flask؟** Reverse proxy: أداء أفضل، وFlask لا يُكشف مباشرة.
- **ما فائدة الـ handlers؟** تعيد بناء/تشغيل الحاويات فقط عندما يتغير ملف، وهذا سر الـ idempotency.
- **كيف تضمن أن النسخ الاحتياطي يعمل؟** `deploy.sh` يشغّله مرة ويتحقق من رفعه إلى S3.
- **ماذا لو تغيّر IP جهازك؟** يُحجب SSH؛ أعد `./deploy.sh` ليحدّث الـ Security Group.

---

## 12) ملاحظات مهمة وصريحة

- المشروع **اختُبر ثابتاً** (syntax / shellcheck / ansible-lint / اختبارات Python / تشغيل `deploy.sh` بأدوات AWS وهمية)، لكنه **لم يُجرَّب على حساب AWS حقيقي** عند كتابته. قد تظهر في أول تشغيل مشكلة بيئة صغيرة (مثل نوع الـ instance أو صلاحيات IAM). الأخطاء تظهر واضحة؛ أصلحها وأعد `./deploy.sh`.
- إذا قال AWS إن `t3.micro` غير مؤهل للـ Free Tier في منطقتك: `export TF_VAR_instance_type=t2.micro`.
- إن كان حسابك (مثل AWS Academy) **يمنع إنشاء IAM Roles**، أخبرني لأعدّل طريقة رفع النسخ الاحتياطي.
- شغّل `terraform -chdir=terraform validate` بعد `init` للتأكد من الصياغة على جهازك.
