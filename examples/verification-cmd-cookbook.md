# Verification Command Cookbook

A reference of concrete `cmd` snippets for `.harness/verification-checks.yaml`.

Use this when `/harness-iterate`'s candidate picker proposes a **fill_needed** entry and you need to write the real command, or when you want to author entries by hand.

This file is intentionally stack-agnostic. Pick the section that matches what your project actually has — not what a generic framework name suggests. If your stack is missing here, the existing entries should be enough scaffolding to derive your own.

---

## How to use

Each section shows:
- **Trigger signal** — what `cmd` is appropriate for
- **`cmd` template** — a runnable shell command with `<placeholders>` you fill in
- **`applicable_when.changed`** — glob suggestion that activates this check
- **Notes** — common gotchas

Drop the snippet into `.harness/verification-checks.yaml` under `checks:` and rename `<...>` to your real paths/services.

---

## Build / compile / typecheck (auto-extractable category)

These exit nonzero if the project doesn't compile. Cheap and high-signal — recommended as the first check most projects add.

### Java + Maven (single module)

```yaml
- id: <module>-build
  cmd: mvn -pl <module-path> -am compile
  timeout: 180
  applicable_when:
    changed: ["<module-path>/**/*.java", "<module-path>/pom.xml"]
```

For polyrepo / nested-clones layouts: replace `<module-path>` with the path relative to the project root. `-am` builds upstream dependencies as needed.

### Java + Maven (full verify, slower)

```yaml
- id: <module>-verify
  cmd: mvn -pl <module-path> -am verify -DskipITs
  timeout: 600
```

`verify` runs unit tests too. Skip `-DskipITs` if you want integration tests, but expect longer timeouts.

### Java + Gradle

```yaml
- id: <module>-check
  cmd: ./gradlew <module-path>:check --quiet
  timeout: 300
  applicable_when:
    changed: ["<module-path>/**/*.{java,kt}", "<module-path>/build.gradle*"]
```

### Kotlin + Gradle (compile only)

```yaml
- id: <module>-compile
  cmd: ./gradlew <module-path>:compileKotlin
  timeout: 180
```

### TypeScript (typecheck only — fastest)

```yaml
- id: <pkg>-typecheck
  cmd: npx tsc --noEmit -p <pkg-path>
  timeout: 60
  applicable_when:
    changed: ["<pkg-path>/**/*.{ts,tsx}"]
```

### Node monorepo (build via workspace script)

```yaml
- id: <pkg>-build
  cmd: npm run --prefix <pkg-path> build
  timeout: 300
```

For pnpm: `pnpm --filter <pkg-name> build`. For yarn: `yarn workspace <pkg-name> build`.

### Python (compile syntax check)

```yaml
- id: <pkg>-compile
  cmd: python -m compileall -q <pkg-path>
  timeout: 60
  applicable_when:
    changed: ["<pkg-path>/**/*.py"]
```

This catches syntax errors without running tests. Pair with `pytest <pkg-path> -x` for behavior.

### Go

```yaml
- id: <pkg>-build
  cmd: go build ./<pkg-path>/...
  timeout: 120
```

### Rust

```yaml
- id: <crate>-check
  cmd: cargo check -p <crate-name> --message-format=short
  timeout: 180
```

---

## Config validation (auto-extractable category)

Pure syntax / schema check. Doesn't deploy anything.

### Docker Compose

```yaml
- id: <stack>-compose-validate
  cmd: docker compose -f <compose-file-path> config
  timeout: 30
  applicable_when:
    changed: ["<dir>/docker-compose*.yml", "<dir>/*.env"]
```

`config` parses and resolves variables. Output is normalized YAML on stdout; nonzero exit on syntax/reference errors.

### Terraform

```yaml
- id: <stack>-tf-validate
  cmd: terraform -chdir=<dir> validate
  timeout: 60
```

Run `terraform -chdir=<dir> init -backend=false` once before this works — `validate` needs provider plugins fetched, but with `-backend=false` it skips remote state.

### Kubernetes manifests (kubeval or kubectl)

```yaml
- id: <stack>-k8s-validate
  cmd: kubectl --dry-run=client apply -f <dir>/
  timeout: 30
```

Or `kubeval <dir>/*.yaml` if installed. `--dry-run=client` doesn't need a live cluster.

### Nginx config

```yaml
- id: <conf>-nginx-validate
  cmd: nginx -t -c <abs-path-to-conf>
  timeout: 10
```

Requires nginx binary. For a dockerized nginx, wrap with `docker run --rm -v "$(pwd):/etc/nginx" nginx:alpine nginx -t`.

### Prisma schema

```yaml
- id: <svc>-prisma-validate
  cmd: npx prisma validate --schema=<path-to-schema.prisma>
  timeout: 30
```

### Alembic (Python SQLAlchemy migrations)

```yaml
- id: alembic-check
  cmd: alembic check
  timeout: 30
  applicable_when:
    changed: ["alembic/versions/**/*.py"]
```

### OpenAPI / JSON Schema

```yaml
- id: openapi-validate
  cmd: npx @apidevtools/swagger-cli validate <path-to-spec.yaml>
  timeout: 30
```

---

## Runtime / smoke (fill_needed category)

These actually exercise the running system. **There is no universal cmd here** — how you start your app, the URL of your health endpoint, how you authenticate, are all project-specific. The snippets below are starting points to adapt.

### Generic "start + curl health" pattern

```yaml
- id: <svc>-startup-smoke
  cmd: |
    <command to start service in background> &
    sleep <warmup seconds>
    curl -sf <health-url>
    rc=$?
    <command to stop service>
    exit $rc
  timeout: 60
```

The pattern is: start, wait for warmup, hit health, capture exit code, stop, propagate. Adapt the start/stop commands and warmup duration to your project.

### Spring Boot fat jar (one-shot run)

```yaml
- id: <svc>-startup
  cmd: |
    java -jar <module>/target/<svc>.jar --server.port=18080 &
    PID=$!
    sleep 20
    curl -sf http://localhost:18080/actuator/health
    rc=$?
    kill $PID
    exit $rc
  timeout: 60
```

`--server.port=18080` avoids colliding with whatever's already running on the default port. Adjust path / port / health endpoint as needed.

### Spring (war on Tomcat embedded)

```yaml
- id: <svc>-startup
  cmd: |
    ./mvnw spring-boot:run -pl <module> -DskipTests &
    PID=$!
    sleep 30
    curl -sf http://localhost:8080/<context>/health
    rc=$?
    kill $PID 2>/dev/null
    exit $rc
  timeout: 90
```

For deployment via a standalone Tomcat, deploy the war to `webapps/` first, then curl — the cmd shape is project-specific enough that this snippet is only a hint.

### Node service (already running on dev server)

```yaml
- id: <svc>-smoke
  cmd: |
    npm run --prefix <dir> dev &
    PID=$!
    npx wait-on http://localhost:3000 --timeout 30000
    curl -sf http://localhost:3000/api/health
    rc=$?
    kill $PID 2>/dev/null
    exit $rc
  timeout: 60
```

`wait-on` is more reliable than fixed `sleep` for waiting on a port. Install with `npm i -g wait-on` or run via npx.

### Single endpoint smoke (when the service is already up via separate process)

```yaml
- id: <svc>-endpoint-smoke
  cmd: curl -sf -H "Authorization: Bearer <token-or-env-var>" <base-url>/<endpoint>
  timeout: 10
  applicable_when:
    changed: ["<controller-path>/**/*.java"]
```

For projects where a long-running dev server already exists in another shell — fastest smoke possible.

### Playwright (smoke-tagged subset)

```yaml
- id: ui-smoke
  cmd: npx playwright test --grep @smoke
  timeout: 300
```

Requires `playwright.config.{ts,js}` and tests tagged with `@smoke`. The full suite via `npx playwright test` without `--grep` is `id: ui-full`, typically gated by `user_hint`.

### Cypress (smoke spec)

```yaml
- id: ui-smoke
  cmd: npx cypress run --spec '**/*smoke*'
  timeout: 300
```

### Custom shell smoke script

```yaml
- id: smoke-script
  cmd: bash <project-root-relative-path>/smoke.sh
  timeout: 300
```

When the project already has a `scripts/smoke.sh` or `bin/smoke`, point to it. The cmd stays one line; the complexity lives in the script.

---

## Database / migration (fill_needed category)

Migrations are tricky because "validating" them properly often requires a real DB.

### MariaDB / MySQL syntax check (no run)

```yaml
- id: <svc>-migration-syntax
  cmd: |
    for f in <migration-dir>/*.sql; do
      mysql --no-defaults -h 127.0.0.1 -u root --silent --skip-column-names -e "EXPLAIN $(cat $f)" 2>&1 | grep -q "ERROR" && { echo "Syntax error in $f"; exit 1; }
    done
    exit 0
  timeout: 60
```

This is best-effort. For real schema-level validation, run against a throwaway DB:

```yaml
- id: <svc>-migration-dryrun
  cmd: |
    docker run --rm -v $PWD/<migration-dir>:/m mariadb:11 sh -c \
      'mysqld --initialize-insecure && mysqld_safe & sleep 5 && mysql -u root -e "CREATE DATABASE test"; for f in /m/*.sql; do mysql -u root test < $f || exit 1; done'
  timeout: 180
```

### PostgreSQL (against existing dev DB)

```yaml
- id: <svc>-pg-migration-check
  cmd: psql -h localhost -U <user> -d <dev-db> -f <migration-file> --single-transaction --set ON_ERROR_STOP=on
  timeout: 60
```

`--single-transaction` rolls back at the end so dev DB stays clean.

---

## Cross-cutting integration (project-defined)

For when you have an actual end-to-end suite — not template-able. Just point at it:

```yaml
- id: integration
  cmd: <your-project's integration runner — e.g. ./gradlew :integrationTest, pytest -m integration, etc.>
  timeout: 600
  applicable_when:
    user_hint: ["integration", "full check"]
```

Gate behind `user_hint` so it only runs when the user explicitly asks — these tend to be 5-10+ minute suites.

---

## What this cookbook deliberately does NOT do

- It does NOT prescribe a way to start your services. `bin/run/<svc>.sh restart` works for one project; `systemctl restart <svc>` for another; `kubectl rollout restart` for a third. Pick what your project uses.
- It does NOT prescribe health-endpoint URLs. `/health`, `/actuator/health`, `/api/<svc>/health`, `/_health` — all valid. Find yours and use it.
- It does NOT prescribe port mappings. The example snippets use one-off ports (18080) to avoid collisions during a check; in your project the real port may be the conventional one.
- It does NOT generate hook scripts under `.harness/hooks/`. If a `cmd` gets long enough to need a separate file, write your own script and point at it (`bash <path-to-script>`).

The harness's stance: detect what's clearly there (manifest files, build commands), suggest categories of checks per cycle, but let the user write project-specific glue.
