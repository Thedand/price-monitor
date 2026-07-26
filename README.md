# Price Monitor

Автоматический сбор обычных и акционных цен эмали ПФ-115 в двух сегментах:

- `economy`: DekArt (Mir Remonta, Farba) и Fazenda (Lursan);
- `standard`: Farbex (Mir Remonta, Farba), Zebra Master (Farba) и
  Корабельная (Lursan).

## Запуск

```powershell
Set-Location D:\Work\price-monitor
.\run.ps1
```

Отдельные этапы:

```powershell
.\collect.ps1
.\analyze.ps1
```

HTML сохраняется в `cache/` на 6 часов, поэтому повторные проверки выполняются
локально. Принудительное обновление:

```powershell
.\collect.ps1 -Refresh
```

## Результаты

- `data/latest.csv` — последнее достоверное состояние;
- `data/history.csv` — история всех запусков (новые строки добавляются);
- `reports/comparison.csv` — минимальная обычная цена и экономия по варианту.
- `reports/ranking.csv` — полный рейтинг всех доступных магазинов по варианту.
- `dashboard/index.html` — интерактивный дашборд сравнения цен.

Данные дашборда обновляются командой `build-dashboard.ps1`, которая автоматически
выполняется в конце `run.ps1`. Откройте `dashboard/index.html` в браузере.

Для анализа используется `regular_price`. На Farba акционная цена сохраняется
отдельно в `promo_price`, но не участвует в выборе лучшей цены.
Farba собирается через разрешённый `sitemap.xml` и публичные карточки товаров;
запрещённый `advanced_search_result.php` не используется. Lursan собирается через
разрешённые категории Fazenda и Корабельная. ПФ-266 и мелкие несопоставимые
фасовки Корабельной исключаются.

Zebra Master выпускается в фасовках 0,8/2,6 кг, тогда как остальные линейки в
основном используют 0,9/2,8 кг. Поэтому отчёты группируют фасовки как `small` и
`large`, а рейтинг строят по `unit_price_per_kg`, сохраняя фактическую фасовку.

## Контроль качества

Сбор отменяется без изменения файлов, если магазин вернул неожиданную страницу,
найдено не ожидаемое количество вариантов для конкретного источника,
обнаружены дубликаты или некорректные цены.

## Добавление товаров

Добавьте товар и источники в `config/products.json`. Для нового сайта потребуется
отдельная функция-адаптер в `collect.ps1`; существующие сайты используют готовые
адаптеры. Алиасы цветов находятся в `config/color-aliases.json`.

## Планировщик Windows

Для ежедневного запуска укажите в Task Scheduler программу `pwsh.exe` и аргументы:

```text
-NoProfile -ExecutionPolicy Bypass -File D:\Work\price-monitor\run.ps1
```

## Автоматический запуск через GitHub

Workflow `.github/workflows/price-monitor.yml` ежедневно в 09:17 по часовому
поясу `Europe/Chisinau` выполняет `run.ps1`, коммитит изменившиеся данные,
отчёты и дашборд обратно в текущую ветку, а затем публикует `dashboard/`
через GitHub Pages.

После загрузки репозитория на GitHub:

1. Откройте **Settings → Actions → General → Workflow permissions** и разрешите
   **Read and write permissions**.
2. Откройте **Settings → Pages → Build and deployment** и выберите источник
   **GitHub Actions**.
3. Перейдите в **Actions → Price monitor → Run workflow** для первого ручного
   запуска.

Если default branch защищена от прямой записи, разрешите GitHub Actions
создавать коммиты либо используйте отдельную ветку данных.
