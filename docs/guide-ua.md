# gssh — швидкий SSH до GCP VM через IAP

`gssh` — це zsh-обгортка над `gcloud compute ssh`, яка додає автодоповнення імен VM по TAB, інтерактивний вибір проєкту/зони через fzf та локальний кеш VM.

## Вимоги

- zsh
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (команда `gcloud` у PATH)
- [fzf](https://github.com/junegunn/fzf) (опціонально — без нього працює вбудований `select`)

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

Відредагуйте файл `~/.gssh/.env` — вкажіть ваші проєкти та зони:

```bash
# Проєкти GCP (обов'язково)
GSSH_PROJECTS="my-production-project my-staging-project"

# Зони (за замовчуванням us-central1-a/b/c)
GSSH_ZONES="us-central1-a us-central1-b us-central1-c europe-west1-b"

# Виключити VM з певним префіксом (наприклад, ноди GKE)
GSSH_EXCLUDE_PREFIXES="gke-"

# GCP акаунти для перемикання (через пробіл)
GSSH_ACCOUNTS="user1@gmail.com user2@company.com"
```

## Використання

```bash
# Підключитися до VM (проєкт/зона — інтерактивно)
gssh my-vm-name

# Вказати проєкт і зону явно
gssh my-vm-name my-project us-central1-a

# Використати конкретний GCP акаунт
gssh -a user@company.com my-vm-name
gssh --account user@company.com my-vm-name my-project us-central1-a

# Прокинути порт (наприклад MySQL)
gssh my-vm-name -- -L 3306:localhost:3306

# Автодоповнення — почніть вводити імʼя і натисніть TAB
gssh mysql-<TAB>

# Оновити кеш VM вручну
gssh --refresh     # або: gssh -r

# Подивитися список VM з кешу
gssh --list        # або: gssh -l
```

## Оновлення

Повторний запуск тієї ж команди оновить `gssh` до актуальної версії. Ваш `.env` залишиться без змін:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/slucheninov/gssh/master/install.sh)
```

## Видалення

```bash
rm -rf ~/.gssh
# Видаліть блок gssh з ~/.zshrc
exec zsh
```
