# gssh - швидкий SSH до GCP VM через IAP

`gssh` - це zsh-обгортка над `gcloud compute ssh`, яка додає автодоповнення акаунтів, VM, проєктів і зон, інтерактивний вибір через fzf та локальний кеш VM з метаданими проєкту й зони.

## Можливості

- автодоповнення для `--account`, імен VM, проєктів і зон;
- окремий кеш VM для кожного GCP акаунта з автоматичною агрегацією та визначенням акаунта;
- автоматичне визначення проєкту/зони з кешу, якщо для VM є один збіг;
- фільтрація VM за literal-префіксами, наприклад `gke-`;
- передача додаткових SSH аргументів після `--`;
- `--dry-run` для перегляду команди і `--copy` для копіювання в буфер;
- атомарне оновлення: усі файли спочатку завантажуються, і лише потім замінюють встановлену версію.

## Вимоги

- zsh
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (команда `gcloud` у PATH)
- [fzf](https://github.com/junegunn/fzf) (опціонально - без нього працює вбудований `select`)

## Встановлення

Одна команда:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/slucheninov/gssh/master/install.sh)
```

Інсталятор скопіює файли в `~/.gssh` і запропонує додати потрібний блок у `~/.zshrc`. Після встановлення перезавантажте шелл:

```bash
exec zsh
```

## Налаштування

Відредагуйте файл `~/.gssh/.env` - вкажіть ваші проєкти, зони та, за потреби, акаунти:

```bash
# Проєкти GCP. Якщо порожньо, буде використано поточний gcloud project
GSSH_PROJECTS="my-production-project my-staging-project"

# Зони (за замовчуванням us-central1-a/b/c)
GSSH_ZONES="us-central1-a us-central1-b us-central1-c europe-west1-b"

# Виключити VM з певним префіксом (наприклад, ноди GKE)
GSSH_EXCLUDE_PREFIXES="gke-"

# GCP акаунти для перемикання (через пробіл)
GSSH_ACCOUNTS="user1@gmail.com user2@company.com"
```

Основні змінні:

| Змінна | Типове значення | Опис |
|---|---|---|
| `GSSH_PROJECTS` | поточний `gcloud` project | Проєкти GCP через пробіл |
| `GSSH_ZONES` | `us-central1-a us-central1-b us-central1-c` | Зони через пробіл |
| `GSSH_CACHE_FILE` | `~/.cache/gssh/vms` | Шлях до кешу VM |
| `GSSH_CACHE_TTL` | `86400` | Час життя кешу в секундах |
| `GSSH_EXCLUDE_PREFIXES` | порожньо | Literal-префікси VM, які треба виключити |
| `GSSH_ACCOUNTS` | порожньо | GCP акаунти для перемикання |

## Використання

```bash
# Підключитися до VM (проєкт/зона - інтерактивно)
gssh my-vm-name

# Вказати проєкт і зону явно
gssh my-vm-name my-project us-central1-a

# Використати конкретний GCP акаунт
gssh -a user@company.com my-vm-name
gssh --account user@company.com my-vm-name my-project us-central1-a

# Прокинути порт (наприклад MySQL)
gssh my-vm-name -- -L 3306:localhost:3306
gssh my-vm-name my-project us-central1-a -- -L 8080:localhost:80 -N

# Оновити кеш VM вручну
gssh --refresh     # або: gssh -r

# Подивитися список VM з кешу
gssh --list        # або: gssh -l

# Показати команду без виконання
gssh --dry-run my-vm-name my-project us-central1-a
gssh -d my-vm-name my-project us-central1-a

# Скопіювати команду в буфер обміну
gssh --copy my-vm-name my-project us-central1-a
gssh -c my-vm-name my-project us-central1-a

# Оновити встановлені файли gssh
gssh --upgrade     # або: gssh -u

# Версія
gssh --version     # або: gssh -V

# Довідка
gssh --help        # або: gssh -h
```

`--dry-run` і `--copy` екранують аргументи з пробілами, тому команди на кшталт `-o "ProxyCommand=ssh host"` можна безпечно вставляти в shell.

## Мульти-акаунт

Коли в `GSSH_ACCOUNTS` вказано кілька адрес, `gssh` працює з усіма автоматично:

- **`gssh --refresh`** - оновлює кеш для кожного акаунта окремо, тихо пропускаючи проєкти, до яких акаунт не має доступу.
- **`gssh --list`** - показує VM з кешів усіх акаунтів.
- **`gssh <vm>`** - знаходить у кеші, якому акаунту належить VM, і використовує його для SSH. Якщо VM є в кількох акаунтах - зʼявиться інтерактивний вибір.
- **`gssh --account <email> <vm>`** - явне вказання акаунта, автоматичне визначення пропускається.

Перед будь-якою операцією `gssh` перевіряє, що всі налаштовані акаунти авторизовані. Якщо акаунт відсутній у `gcloud auth list`, ви побачите:

```
gssh: the following accounts are not authenticated:
  - user@company.com

Run the following to authenticate:
  gcloud auth login user@company.com
```

### Приклад

```bash
# .env
GSSH_ACCOUNTS="dev@company.com ops@company.com"
GSSH_PROJECTS="dev-project-123 staging-456 prod-789"
```

```bash
$ gssh --refresh
  ⠙ gssh: refreshing cache for dev@company.com...
  ⠙ gssh: refreshing cache for ops@company.com...
gssh: cache refreshed (42 VMs across 2 accounts)

$ gssh --list          # VM з обох акаунтів
mysql-primary-01       # ops@company.com / prod-789
mysql-staging-01       # dev@company.com / staging-456
...

$ gssh mysql-primary-01   # автоматично визначає ops@company.com
gssh: connecting to mysql-primary-01 | account: ops@company.com | project: prod-789 | zone: us-central1-a
```

## Кеш

Кеш оновлюється автоматично, коли його немає, коли він застарів або коли файл має старий формат лише з іменами VM. Усередині кеш зберігає імʼя VM, проєкт і зону, тому `gssh` може звузити автодоповнення та пропустити інтерактивний вибір, якщо для VM є один збіг.

Для кожного акаунта створюється окремий файл кешу на основі `GSSH_CACHE_FILE`:

```text
~/.cache/gssh/dev_company_com_vms
~/.cache/gssh/ops_company_com_vms
```

Коли налаштовано кілька акаунтів, проєкт, до якого один акаунт не має доступу (permission denied), тихо пропускається - його підхопить акаунт, який має доступ. Кеш оновлюється, якщо хоча б один проєкт відпрацював успішно.

Оновлення кешу атомарне: `gssh` спочатку пише тимчасовий файл і залишає старий кеш, якщо всі проєкти для акаунта завершились помилкою.

## Автодоповнення

Автодоповнення працює для:

- значень `--account` / `-a` із `GSSH_ACCOUNTS`;
- імен VM з кешу вибраного акаунта;
- проєктів із `GSSH_PROJECTS` або кешованих метаданих VM;
- зон із `GSSH_ZONES` або кешованих метаданих VM.

```bash
gssh -a <TAB>
gssh mysql-<TAB>
gssh mysql-primary-01 <TAB>
gssh mysql-primary-01 production-project <TAB>
```

Для роботи completion переконайтеся, що рядок `fpath=("${HOME}/.gssh" $fpath)` додано до `~/.zshrc` перед `compinit`.

## Upgrade / Оновлення

Можна оновитися командою:

```bash
gssh --upgrade
```

`gssh` спочатку завантажує всі файли й замінює встановлену версію лише після успішного завантаження. Файл `~/.gssh/.env` не змінюється.

Або повторно запустити installer. Ваш `.env` залишиться без змін:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/slucheninov/gssh/master/install.sh)
```

## Видалення

```bash
chmod +x uninstall.sh
./uninstall.sh
# Видаліть блок gssh з ~/.zshrc, якщо він залишився
exec zsh
```
