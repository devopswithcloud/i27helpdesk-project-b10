# i27 Helpdesk — Local Setup Guide

A step-by-step guide to get all 6 services of the i27 Helpdesk product running on your local machine.

## Architecture Overview

```
                                          ┌──> Auth Service (Java)       :8081 ──┐
                                          │                                      │
UI (Next.js) ──> Gateway (Node.js) ──────┼──> Ticket Service (Java)     :8082 ──┤
   :3000            :8080                │                                      ├──> MySQL
                                          ├──> Comment Service (Python) :8083 ──┤   (136.65.46.225:3306/helpdesk_dev)
                                          │                                      │
                                          └──> Notification Service (Py):8084 ──┘
```

The Gateway only proxies HTTP requests to the four services — it does **not** talk to MySQL itself. Each of Auth, Ticket, Comment, and Notification holds its own DB connection to the shared `helpdesk_dev` database.

| # | Service                  | Language | Port | Folder                              |
|---|---------------------------|----------|------|--------------------------------------|
| 1 | UI                        | Next.js  | 3000 | `i27-helpdesk-ui`                    |
| 2 | Gateway                   | Node.js  | 8080 | `i27-helpdesk-gateway`                |
| 3 | Auth Service               | Java     | 8081 | `i27-helpdesk-auth-service`           |
| 4 | Ticket Service             | Java     | 8082 | `i27-helpdesk-ticket-service`         |
| 5 | Comment Service            | Python   | 8083 | `i27-helpdesk-comment-service`        |
| 6 | Notification Service       | Python   | 8084 | `i27-helpdesk-notification-service`   |

**Prerequisites:** Java + Maven, Python, Node.js, and access to the MySQL database.

**Important:** Start services roughly in this order — DB → Auth → Ticket → Comment → Notification → Gateway → UI — since the Gateway and downstream services depend on each other being reachable.

---

## Step 1 — Auth Service (Java, port 8081)

1. Navigate to the `i27-helpdesk-auth-service` folder.
2. Create the file `src/main/resources/application-local.yaml` with:

   ```yaml
   server:
     port: 8081
   spring:
     datasource:
       url: jdbc:mysql://136.65.46.225:3306/helpdesk_dev
       username: helpdesk_user
       password: Gcp@2024
   jwt:
     secret: i27academy-secret-key-which-is-32chars
     expiryMillis: 3600000
   ```

3. Start the service:

   ```bash
   mvn spring-boot:run -Dspring-boot.run.profiles=local
   ```

4. Verify it's up at `http://localhost:8081`.

---

## Step 2 — Ticket Service (Java, port 8082)

1. Navigate to the `i27-helpdesk-ticket-service` folder.
2. Create the file `src/main/resources/application-local.yaml` with:

   ```yaml
   server:
     port: 8082
   spring:
     datasource:
       url: jdbc:mysql://136.65.46.225:3306/helpdesk_dev
       username: helpdesk_user
       password: Gcp@2024
   jwt:
     secret: i27academy-secret-key-which-is-32chars
     expiryMillis: 3600000
   ```

3. Start the service:

   ```bash
   mvn spring-boot:run -Dspring-boot.run.profiles=local
   ```

4. Verify it's up at `http://localhost:8082`.

---

## Step 3 — Comment Service (Python, port 8083)

1. Navigate to the `i27-helpdesk-comment-service` folder.
2. Create the file `.env.local` with:

   ```
   DB_USER=helpdesk_user
   DB_PASSWORD=Gcp@2024
   DB_HOST=136.65.46.225
   DB_PORT=3306
   DB_NAME=helpdesk_dev

   NOTIFICATION_URL=http://localhost:8084/notifications/event
   TICKET_SERVICE_URL=http://localhost:8082/tickets
   ```

3. Install dependencies and start the service:

   ```bash
   python -m pip install -r requirements.txt
   python -m uvicorn app.main:app --reload --port 8083
   ```

   > Note: the command is `uvicorn`, not `unicorn` — `unicorn` is a typo carried over from the original notes.

4. Verify it's up at `http://localhost:8083`.

---

## Step 4 — Notification Service (Python, port 8084)

1. Navigate to the `i27-helpdesk-notification-service` folder.
2. Create the environment variables needed for the DB and SMTP mailer (per the service's own `readme.md`). On Windows `cmd`:

   ```cmd
   set DATABASE_URL="mysql+pymysql://helpdesk_user:Gcp%402345@136.65.46.225:3306/helpdesk_dev"
   set SMTP_HOST=smtp.gmail.com
   set SMTP_PORT=587
   set SMTP_USER=<your-smtp-user>
   set SMTP_PASSWORD=<your-smtp-password>
   ```

   > Adjust `DATABASE_URL` credentials/host to match the shared DB (`136.65.46.225` / `helpdesk_user` / `Gcp@2024`) — the sample in the service readme used different placeholder values. Also confirm with the team which SMTP account to use for local testing.

3. Install dependencies and start the service:

   ```bash
   python -m pip install -r requirements.txt
   python -m uvicorn app.main:app --reload --port 8084
   ```

4. Verify it's up at `http://localhost:8084`.

---

## Step 5 — Gateway (Node.js, port 8080)

1. Navigate to the `i27-helpdesk-gateway` folder.
2. Create the file `.env.local` with:

   ```
   SERVER_PORT=8080
   UI_ORIGIN=http://localhost:3000

   AUTH_SERVICE_URL=http://localhost:8081
   TICKET_SERVICE_URL=http://localhost:8082
   COMMENT_SERVICE_URL=http://localhost:8083
   ATTACHMENT_SERVICE_URL=http://localhost:8084

   JWT_SECRET=i27academy-secret-key-which-is-32chars
   ```

   > `ATTACHMENT_SERVICE_URL` is pointed at port 8084, which in this project is the Notification Service — keep this as-is unless there's a separate attachment service, in which case confirm the correct URL.

3. Install dependencies and start the service:

   ```bash
   npm install
   npm run dev
   ```

4. Verify it's up at `http://localhost:8080`.

---

## Step 6 — UI (Next.js, port 3000)

1. Navigate to the `i27-helpdesk-ui` folder.
2. Create the file `.env.local` with:

   ```
   NEXT_PUBLIC_API_BASE_URL=http://localhost:8080
   ```

3. Install dependencies and start the app:

   ```bash
   npm install
   npm run dev
   ```

4. Open `http://localhost:3000` in your browser. The login page is at `http://localhost:3000/auth/login`.

---

## Database Setup

- Host: `136.65.46.225`, Port: `3306`, DB: `helpdesk_dev`, User: `helpdesk_user`, Password: `Gcp@2024`
- Database is provisioned but starts empty — the schema is loaded manually (not auto-created by the apps). Use `helpdesk_dev_full_backup.sql` in the project root to restore the schema/data.
- Seed data needed for roles and an initial admin login:

  ```sql
  INSERT INTO roles (role_name)
  VALUES ('USER'), ('AGENT'), ('ADMIN');

  INSERT INTO users (email, password_hash, full_name, status)
  VALUES (
      'siva@i27academy.com',
      '$2a$12$qDxPJt4sQGsHz8NfxCH.sOkPcQTfL/7Ms5B7eFL7wtcF5jaSRbgUG',
      'System Admin',
      'ACTIVE'
  );

  INSERT INTO user_roles (user_id, role_id)
  VALUES (
      (SELECT id FROM users WHERE email = 'siva@i27academy.com'),
      6  -- verify this matches the ADMIN role_id generated in your roles table
  );
  ```

- Default admin login: `siva@i27academy.com` / `admin123`

### User roles

| Role  | Access                                             |
|-------|-----------------------------------------------------|
| USER  | Student — create tickets, add comments               |
| AGENT | Support — work on tickets assigned to them            |
| ADMIN | Super access — user creation, ticket assignment        |

---

## Full Startup Checklist

- [ ] MySQL reachable at `136.65.46.225:3306`, schema loaded from `helpdesk_dev_full_backup.sql`, roles + admin user seeded
- [ ] Auth Service running on 8081 (`application-local.yaml` created)
- [ ] Ticket Service running on 8082 (`application-local.yaml` created)
- [ ] Comment Service running on 8083 (`.env.local` created)
- [ ] Notification Service running on 8084 (env vars set)
- [ ] Gateway running on 8080 (`.env.local` created)
- [ ] UI running on 3000 (`.env.local` created)
- [ ] Login works at `http://localhost:3000/auth/login` with the admin credentials above

## Open Questions / Things to Confirm

These were unclear or incomplete in the original notes (`revision.md`) and are worth confirming with the team before relying on them:

1. **Notification service env vars** weren't listed in `revision.md` (the file cuts off) — the values above were pulled from `i27-helpdesk-notification-service/readme.md`, which uses different placeholder DB credentials than the rest of the stack. Confirm the correct `DATABASE_URL` and SMTP credentials to use.
2. **`python -m unicorn`** in the original notes should be `python -m uvicorn` (typo) — corrected above for both Comment and Notification services.
3. **`ATTACHMENT_SERVICE_URL=http://localhost:8084`** in the Gateway config points at the Notification Service port — confirm whether this is intentional or if a separate attachment service is expected.
