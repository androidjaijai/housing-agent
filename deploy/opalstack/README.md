# 部署去 Opalstack（共享主機）

呢份係俾**你**睇嘅。部署工作由你部機上面嘅 Claude Code 做，佢會跟 `deploy/opalstack/CLAUDE-DEPLOY.md` 一步步行，每個會改伺服器嘅指令都會先問你。

流程：本機用 age 私鑰解密 → `rsync` 上傳去 Opalstack → 喺伺服器 `composer install`。**私鑰永遠只喺你部機，唔會上傳、唔會 commit、唔好貼俾 Claude。**

## 你要準備乜

1. Opalstack 帳戶（https://my.opalstack.com），同埋一個你控制嘅域名（可以改 DNS）。
2. 本機裝好：`claude`（Claude Code）、`age`、`git`、`ssh`、`rsync`、PHP 8.3+ 同 Composer（用嚟本機整 `APP_KEY`）。
3. age 私鑰檔案，放喺 repo **外面**，例如 `~/keys/housing-agent-private-key.txt`，然後 `chmod 600` 佢。
4. 一條 SSH key（`ssh-keygen -t ed25519`），公鑰要加落 Opalstack（見下面第 1 步）。

## 喺 Opalstack 控制台要開嘅嘢

具體畫面同選項可能會變，以 Opalstack 當時嘅介面同 https://docs.opalstack.com 為準。

1. **Shell user + SSH key**：開一個 shell user，將你嘅 SSH 公鑰加落去。本機試 `ssh <user>@<server>` 登入到先繼續。
2. **App（類型 `PHP-FPM Nginx Symlink`）**：揀 **PHP 8.3 或以上**。Laravel 13 最低要 8.3；如果控制台冇 8.3，**停低**，開 support ticket 問 Opalstack，或者轉其他主機。Symlink 目標填 `/home/<user>/apps/housing_agent/current/public`（`housing_agent` 就係你之後設嘅 `OPAL_APP_DIR`）。參考：https://docs.opalstack.com/topic-guides/symlinks/
3. **Site**：加你嘅域名（例如 `www.example.com`），Routes 嘅 URI `/` 指去上面個 app；開 **Let's Encrypt**（免費 SSL），同埋 **HTTPS redirect**。
4. **MariaDB 資料庫同用戶**：喺控制台開一個 database 同一個 user，記低資料庫名、用戶名、密碼同主機名（主機名唔好估，抄控制台顯示嗰個）。
5. **Mailbox**：開一個郵箱（例如 `hello@你嘅域名`），用嚟經 SMTP 寄通知同重設密碼電郵。記低 SMTP 主機、port、用戶名、密碼。
6. **DNS**：將域名嘅 A 記錄（或 CNAME）指去 Opalstack 俾你嘅 IP / 主機，等生效。有 Let's Encrypt 嘅話，DNS 要先指啱。

（進階：Opalstack 亦有 API，https://my.opalstack.com/api/v1/ ，唔係必要。）

## 點樣叫本機 Claude 部署

```bash
git clone -b claude/interactive-demo https://github.com/androidjaijai/housing-agent.git
cd housing-agent
claude
```

喺 Claude 入面，按次序行：

1. `/deploy-opalstack preflight`：檢查本機工具、私鑰、SSH、伺服器 PHP 版本同擴充。有問題佢會教你點修。
2. `/deploy-opalstack first-run`：喺伺服器開好資料夾，上傳 `.env` 範本。之後**你**自己改伺服器上嘅 `.env`：
   `ssh -t <OPAL_SSH> nano <OPAL_APP_DIR>/shared/.env`
   （填 DB、MAIL、`APP_URL`、`APP_KEY` 等，Claude 會逐項講邊度攞值。Claude 唔會顯示 `.env` 內容。）
3. `/deploy-opalstack deploy`：先 dry-run，再真正部署（解密、上傳、`composer install`、備份資料庫、`migrate`、切換版本）。

之後 Claude 會帶你開第一個 admin（`make:filament-user`，**唔會**灌 demo 資料）、設定 cron、逐項驗證。你亦可以直接用口語講，例如「幫我部署去 Opalstack」，Claude 會跟同一份手冊。

設定檔：`cp deploy/opalstack/opalstack.env.example deploy/opalstack/opalstack.env` 再填（Claude 會幫你；呢個檔唔會入 git）。主要變數：`OPAL_SSH`、`OPAL_APP_DIR`、`OPAL_PHP`、`OPAL_COMPOSER`、`OPAL_URL`、`AGE_KEY_FILE`、`DEPLOY_BRANCH`、`KEEP_RELEASES`。

## 上線前要做

來自 `app-src/docs/SECURITY-TESTS.md`：

1. 刪除或改晒 demo 帳戶（`admin@`、`agent@`、`assistant@example.com`，密碼 `password`）。Production 唔好灌 demo 資料。
2. 所有 Admin 開 MFA。
3. `.env`：`APP_DEBUG=false`、`SESSION_SECURE_COOKIE=true`、`APP_URL` 同正式域名一致。
4. 備份：資料庫備份有出，同埋做一次**還原演練**。最好加 off-server 備份（例如 S3）。
5. 跑 OWASP ZAP baseline（對 staging 或正式網址）；SSL Labs 目標 A 或以上。
6. 檢查回應 header 冇 `X-Powered-By`；有就問 Opalstack 或睇能否設 `expose_php = Off`。
7. 私鑰同 `.env` 分開保存，唔好放喺伺服器。
8. 填好 admin **Settings**（公司名、牌照號碼、地址、WhatsApp）。

## 出事點算

- **回滾上一版**：叫 Claude `/deploy-opalstack rollback`，或本機行 `deploy/opalstack/opalstack-deploy.sh rollback`。
- **睇狀態**：`deploy/opalstack/opalstack-deploy.sh status`；網頁睇 `https://你嘅域名/health`（200 即正常）。
- **睇 log**：`ssh <OPAL_SSH> tail -n 100 <OPAL_APP_DIR>/shared/storage/logs/laravel-*.log`。
- 500 / 白頁 / 403 / 重複轉址：Claude 手冊有對照表，直接話俾佢聽現象。
- 唔好叫 Claude 亂改伺服器；佢遇到失敗會停低同報告。

## 限制

- 共享主機記憶體有限：`composer install` 可能爆記憶體（會用 `COMPOSER_MEMORY_LIMIT=-1`）；圖片處理同大批量匯入要慢啲。
- 冇 root、冇 supervisor：隊列靠 cron 每分鐘行 `queue:work --stop-when-empty`，所以電郵、翻譯等背景工作**最多有約 1 分鐘延遲**。
- 排程（備份、提醒）同樣靠 cron 每分鐘行 `schedule:run`；cron 未裝嘅話 `/health` 會報 scheduler 唔正常。
- Opalstack 嘅 PHP 版本、路徑、SMTP / 資料庫主機等細節以控制台同官方文件為準，部署時 Claude 會核實。
