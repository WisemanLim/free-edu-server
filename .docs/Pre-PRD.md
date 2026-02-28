<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# Ubuntu에 아래와 같은 서비스를 구축하고자 합니다. 가능하다면 docker-compose로 구성해 주세요. 단, docker-compose 를 패키지 등도 설치해야 합니다.

전제 : 온라인으로 외부에서 접속이 가능해야 합니다.

1. 테스트를 위한 postgresql, mariadb를 지원합니다. data volume을 별도로 설정합니다. 웹관리 툴을 제공합니다.
2. python 코드 연습을 위한 jupyter notebook을 제공, node, go 등의 연습의 위한 vscode(server)를 제공합니다. 웹기반의 ide 환경을 제공합니다.
3. 기본 접속 환경은 https 접속만을 지원해야 합니다.
4. ssh로 접속시 ssh client 툴 외에 웹으로 접근이 가능한 환경을 제공합니다.

* 내부/외부 포트를 다르게 구성할 수 있어야 합니다.

각 단계에 필요한 docker-compose 파일을 독립적으로 구성하여 개별로 배포 및 기동/중지 등이 가능하도록 합니다. 인프라에 지식이 없는 대상자를 위한 아주 상세한 가이드를 작성해 주세요.

Ubuntu 기반으로 “온‑프레미스/클라우드 서버 + 외부 HTTPS 접속”을 전제로,

1) DB 웹 관리 환경,
2) Python/Node/Go 웹 IDE 환경,
3) 웹 SSH 터미널 환경
을 각각 **독립적인 `docker-compose.yml`** 로 나누어 구성해 드립니다.

아래는 **인프라/도커/보안/네트워크까지 완전 초보자용 단계별 가이드**입니다.

***

## 1. 전제: 서버 설정 및 HTTPS 기반

### 1‑1. Ubuntu 서버 기본 가정

- OS: Ubuntu 22.04 LTS (또는 24.04 LTS)
- 외부에서 `https://your-domain.com` 또는 `https://IP:PORT`로 접속.
    - 도메인 사용 권장 (예: `dev.example.com`).
- 방화벽: `ufw` 또는 Cloud Provider의 Security Group에서 포트 허용.


### 1‑2. 도커 + docker‑compose 설치 (Ubuntu)

```bash
# 1. 패키지 업데이트
sudo apt update && sudo apt upgrade -y

# 2. 도커 설치에 필요한 패키지 설치
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# 3. Docker 공식 GPG 키 등록
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 4. Docker apt 저장소 추가
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. 설치
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 6. 도커 그룹에 사용자 추가 (sudo 없이 도커 사용)
sudo usermod -aG docker $(whoami)

# 7. 재로그인 후 확인
docker --version
docker compose version
```

> 재로그인하거나 `su - $USER`로 다시 세션 열기.[^1_1][^1_2][^1_3][^1_4]

***

## 2. DB 구성 (PostgreSQL + MariaDB + Adminer)

### 2‑1. 디렉토리 및 구조

```bash
mkdir -p ~/labs/db
cd ~/labs/db
```


### 2‑2. `docker-compose-db.yml`

```yaml
# docker-compose-db.yml
version: '3.9'

services:
  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_USER: dbuser
      POSTGRES_PASSWORD: dbpass
      POSTGRES_DB: postgres_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-postgres:/docker-entrypoint-initdb.d
    networks:
      - db_net

  mariadb:
    image: mariadb:10
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_USER: dbuser
      MYSQL_PASSWORD: dbpass
      MYSQL_DATABASE: mariadb_db
    volumes:
      - mariadb_data:/var/lib/mysql
      - ./init-mariadb:/docker-entrypoint-initdb.d
    networks:
      - db_net

  adminer:
    image: adminer:latest
    restart: unless-stopped
    ports:
      - "3080:8080"  # 외부:3080 → 컨테이너:8080
    networks:
      - db_net

volumes:
  postgres_data:
  mariadb_data:

networks:
  db_net:
    driver: bridge
```

- `init-postgres/` 및 `init-mariadb/` 폴더를 만들고 `.sql` 파일을 둘 수 있음 (초기 DB 스키마 준비용).[^1_5][^1_6][^1_7]


### 2‑3. 구동/종료

```bash
# up
docker-compose -f docker-compose-db.yml up -d

# down
docker-compose -f docker-compose-db.yml down

# 로그 확인
docker-compose -f docker-compose-db.yml logs -f
```

- 초기 접속: `http://서버IP:3080` → Adminer에서
    - PostgreSQL: Hostname `postgres`, 유저 `dbuser`, 비번 `dbpass`
    - MariaDB: Hostname `mariadb`, 유저 `dbuser`, 비번 `dbpass`

포트를 바꾸고 싶으면 `ports: - "외부포트:8080"`만 수정하면 됩니다.

***

## 3. Python + Web IDE (Jupyter + code‑server)

### 3‑1. 디렉토리 구조

```bash
mkdir -p ~/labs/ide
cd ~/labs/ide
mkdir -p notebooks    # Jupyter 노트북 저장소
mkdir -p projects     # 코드 서버 작업 디렉토리
```


### 3‑2. `docker-compose-ide.yml` (Jupyter + code‑server)

```yaml
# docker-compose-ide.yml
version: '3.9'

services:
  jupyter:
    image: jupyter/datascience-notebook:latest
    restart: unless-stopped
    ports:
      - "3090:8888"  # 외부:3090 → Jupyter:8888
    environment:
      JUPYTER_ENABLE_LAB: "yes"
    volumes:
      - ./notebooks:/home/jovyan/work
    command: start-notebook.sh --NotebookApp.token='your-jupyter-token'

  code-server:
    image: codercom/code-server:latest
    restart: unless-stopped
    ports:
      - "3091:8080"  # 외부:3091 → code-server:8080
    volumes:
      - ./projects:/home/coder/project
      - ./config-code/.config:/home/coder/.config
      - ./config-code/.local:/home/coder/.local
    environment:
      PASSWORD: "your-codeserver-password"

networks:
  default:
    driver: bridge
```

- Jupyter 접속: `http://서버IP:3090?token=your-jupyter-token`
- code‑server (VSCode‑style 웹 IDE) 접속: `http://서버IP:3091` → 비밀번호 `your-codeserver-password` 입력.[^1_8][^1_9][^1_10][^1_11]


### 3‑3. 구동/종료

```bash
docker-compose -f docker-compose-ide.yml up -d
docker-compose -f docker-compose-ide.yml down
```


***

## 4. 웹 기반 SSH 터미널 (ttyd)

### 4‑1. 디렉토리 구조

```bash
mkdir -p ~/labs/ssh
cd ~/labs/ssh
```


### 4‑2. `docker-compose-ttyd.yml` (웹 SSH 터미널)

```yaml
# docker-compose-ttyd.yml
version: '3.9'

services:
  ttyd:
    image: tsl0922/ttyd:latest
    restart: unless-stopped
    ports:
      - "3100:7681"  # 외부:3100 → ttyd:7681
    command: bash -l
    environment:
      - HTTP_USERNAME=ttyuser
      - HTTP_PASSWORD=ttypass
      # - ENABLE_SSL=true   # 나중에 reverse proxy + SSL을 쓰면 이건 뺀다
    volumes:
      - /home:/home:ro
      - /etc:/etc:ro
```

- 접속: `http://서버IP:3100` → HTTP 기본 인증 `ttyuser` / `ttypass` 입력 후, bash 터미널 사용.[^1_12][^1_13][^1_14]


### 4‑3. 구동/종료

```bash
docker-compose -f docker-compose-ttyd.yml up -d
docker-compose -f docker-compose-ttyd.yml down
```


***

## 5. HTTPS 기반 외부 접속 (certbot + nginx reverse proxy)

### 5‑1. 전제: 도메인과 포트 구조

- 도메인: 예 `dev.example.com`
- 외부 HTTPS: 443 포트
- 내부 서비스들은 각각 다른 포트(예: 3080, 3090, 3091, 3100)로 띄우고, Nginx가 443을 받아서 경로별로 라우팅.

예시:


| 경로 | 역할 |
| :-- | :-- |
| `https://dev.example.com/db` | Adminer (DB 웹 관리) |
| `https://dev.example.com/jupyter` | Jupyter |
| `https://dev.example.com/ide` | code‑server |
| `https://dev.example.com/tty` | ttyd (웹 SSH) |

### 5‑2. Nginx + certbot 설치

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
sudo ufw app list
sudo ufw allow 'Nginx Full'
sudo ufw allow 22
```


### 5‑3. Nginx 설정 예 (`/etc/nginx/sites-available/dev.example.com`)

```nginx
server {
    listen 80;
    server_name dev.example.com;

    # DB Adminer
    location /db/ {
        proxy_pass http://127.0.0.1:3080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Jupyter
    location /jupyter/ {
        proxy_pass http://127.0.0.1:3090/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # code-server
    location /ide/ {
        proxy_pass http://127.0.0.1:3091/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # ttyd
    location /tty/ {
        proxy_pass http://127.0.0.1:3100/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Certbot 인증용
    location ~ /.well-known/acme-challenge {
        root /var/www/html;
    }
}
```

활성화:

```bash
sudo ln -s /etc/nginx/sites-available/dev.example.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```


### 5‑4. Let’s Encrypt SSL 인증서 발급

```bash
sudo certbot --nginx -d dev.example.com
```

이후 `HTTPS`로만 접속.
`http://dev.example.com/db` → `https://dev.example.com/db` 등으로 자동 리다이렉트 됨.[^1_15][^1_3][^1_14]

***

## 6. “내부/외부 포트를 다르게” 구성하기

각 `docker-compose-*.yml`에서 `ports` 항목만 수정하면 됩니다.

예:

```yaml
ports:
  - "외부포트:내부포트"
```

- Adminer:
    - 현재: `3080:8080` → `외부:3080` → `컨테이너:8080`
    - 변경 예: `4080:8080` → `외부:4080` 사용.
- Jupyter:
    - `3090:8080` → `4090:8080` 등으로 바꾸고, nginx location도 `proxy_pass http://127.0.0.1:4090/`로 변경.

각 스택(`db`, `ide`, `ssh`)은 서로 독립 `docker-compose.yml` 이므로,

- DB 스택: `docker-compose -f ~/labs/db/docker-compose-db.yml up -d`
- IDE 스택: `docker-compose -f ~/labs/ide/docker-compose-ide.yml up -d`
- SSH 스택: `docker-compose -f ~/labs/ssh/docker-compose-ttyd.yml up -d`
처럼 각각 기동/중지/업데이트 가능합니다.[^1_2][^1_3][^1_1]

***

## 7. 보안/운영 팁 (초보자용)

- 비밀번호/토큰: 실제 운영 시 `your-jupyter-token`, `your-codeserver-password`, `ttypass` 등은 **랜덤 강한 패스워드**로 변경.
- 방화벽: 외부에서 직접 `3080`, `3090`, `3091`, `3100` 열어두지 말고, **Nginx + HTTPS 443 만 허용** 권장.
- 도커 권한: 일반 사용자를 `sudo usermod -aG docker`로 등록하지 않으려면 `sudo` 명령으로만 실행.
- 감사/로그: `sudo docker logs <컨테이너명>` 또는 `docker-compose -f ... logs -f`로 실시간 모니터링.

***

원하시면 다음 단계로:

- DB/IDE/SSH 스택을 모두 한 `docker-compose.yml`로 통합하는 버전
- 도커 + Kubernetes + predecessors로 확장하는 버전
을 별도로 구성해 드리겠습니다.
지금까지 구조가 괜찮다면, 서버 IP/도메인, 원하는 외부 포트(예: 20000~30000대)를 알려주시면 그에 맞춰 **포트 테이블 + 설정 예시**를 다시 정리해 드리겠습니다.
<span style="display:none">[^1_16][^1_17][^1_18][^1_19][^1_20][^1_21][^1_22][^1_23][^1_24][^1_25][^1_26][^1_27][^1_28][^1_29][^1_30]</span>

<div align="center">⁂</div>

[^1_1]: https://docs.docker.com/engine/install/ubuntu/

[^1_2]: https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-compose-on-ubuntu-22-04

[^1_3]: https://docs.docker.com/compose/install/linux/

[^1_4]: https://younyellow.tistory.com/8

[^1_5]: https://www.reddit.com/r/docker/comments/g77ldf/connect_adminer_to_postgresql/

[^1_6]: https://noggame.tistory.com/80

[^1_7]: https://jackerlab.com/docker-adminer-lightweight-multi-database-management-tool/

[^1_8]: https://github.com/nezhar/jupyter-docker-compose

[^1_9]: https://jackerlab.com/docker-coder-code-server/

[^1_10]: https://dev.to/hassan_aftab/jupyter-notebooks-in-docker-4a29

[^1_11]: https://docs.docker.com/guides/jupyter/

[^1_12]: https://hub.docker.com/r/tsl0922/ttyd

[^1_13]: https://github.com/Cp0204/ttydBridge

[^1_14]: https://devopslog.tistory.com/172

[^1_15]: https://stackoverflow.com/questions/78838701/adminer-on-docker-compose-how-to-secure-connection

[^1_16]: https://god-logger.tistory.com/117

[^1_17]: https://aquaheyday.tistory.com/entry/ubuntu-2204-에-Docker-Docker-compose-설치

[^1_18]: https://gist.github.com/kolosek/78084afcb677f9ea9048b616335ffa02

[^1_19]: https://github.com/RamiKrispin/vscode-python

[^1_20]: https://attic2020.tistory.com/entry/Docker-compose를-사용해서-PythonMySql-개발환경-만들기-VSCode

[^1_21]: https://parkkingcar.tistory.com/195

[^1_22]: https://89douner.tistory.com/123

[^1_23]: https://developers-haven.tistory.com/73

[^1_24]: https://newhaw.tistory.com/78

[^1_25]: https://cuire.tistory.com/85

[^1_26]: https://github.com/stefanproell/jupyter-notebook-docker-compose

[^1_27]: https://bundw.tistory.com/15

[^1_28]: https://bundw.tistory.com/69

[^1_29]: https://blog.naver.com/sqlpro/223267185216

[^1_30]: https://velog.io/@sound/code-server-setup


---

# 2. DB 구성 (PostgreSQL + MariaDB + Adminer) 에서 postgresql, mariadb에 대한 외부 접속이 가능하도록 docker-compose-db.yml을 수정합니다.

postgresql과 mariadb를 **외부에서 직접 접속** 가능하도록 하려면,

1) `docker-compose-db.yml`에서 각 DB에 `ports`를 추가해서 `호스트(우분투 서버)`로 포트를 노출하고,
2) 필요 시 `listen_addresses` 설정을 `*`로 열어 두면 됩니다.
(아래는 “외부에서 직접 DB 접속” + 현재 Adminer도 유지하는 형태로 수정한 예시입니다.)

***

### 수정된 `docker-compose-db.yml` (PostgreSQL + MariaDB 외부 접속 가능)

```yaml
# docker-compose-db.yml
version: '3.9'

services:
  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_USER: dbuser
      POSTGRES_PASSWORD: dbpass
      POSTGRES_DB: postgres_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-postgres:/docker-entrypoint-initdb.d
    ports:
      - "5433:5432"   # 외부:5433 → 컨테이너:5432  (내부 포트는 그대로 5432 유지)
    networks:
      - db_net

  mariadb:
    image: mariadb:10
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_USER: dbuser
      MYSQL_PASSWORD: dbpass
      MYSQL_DATABASE: mariadb_db
    volumes:
      - mariadb_data:/var/lib/mysql
      - ./init-mariadb:/docker-entrypoint-initdb.d
    ports:
      - "3307:3306"   # 외부:3307 → 컨테이너:3306  (내부 포트는 3306 유지)
    networks:
      - db_net

  adminer:
    image: adminer:latest
    restart: unless-stopped
    ports:
      - "3080:8080"   # 외부:3080 → Adminer:8080 (웹 DB 관리)
    networks:
      - db_net

volumes:
  postgres_data:
  mariadb_data:

networks:
  db_net:
    driver: bridge
```

- `ports` 이해:
    - `- "외부포트:내부포트"` 형식
    - 위 예:
        - PostgreSQL: 서버의 `5433` 포트로 들어오면 컨테이너의 `5432`로 전달.
        - MariaDB: 서버의 `3307` 포트로 들어오면 컨테이너의 `3306`으로 전달.[^2_1][^2_2][^2_3]

***

### 1. 외부에서 접속하는 예시

외부에서 직접 접속하는 DB 클라이언트(예: DBeaver, Navicat, VS Code PostgreSQL/MariaDB 확장 등)에서:

- **PostgreSQL**:
    - Host: `dev.example.com` 또는 `서버IP`
    - Port: `5433`
    - User: `dbuser`
    - Password: `dbpass`
    - DB: `postgres_db`
- **MariaDB**:
    - Host: `dev.example.com` 또는 `서버IP`
    - Port: `3307`
    - User: `dbuser`
    - Password: `dbpass`
    - DB: `mariadb_db`

Adminer(`https://dev.example.com/db`)는 외부에서 `http://서버IP:3080` 또는 `https://dev.example.com/db`로 접속해도

- Server: `postgres` (내부 호스트명)
- Server: `mariadb`
로 여전히 접근 가능합니다.

***

### 2. 외부 포트를 다르게 두고 싶을 때

- 예: PostgreSQL 외부 포트를 `8001`, MariaDB 외부 포트를 `8002`로 하고 싶다면:

```yaml
postgres:
  ...
  ports:
    - "8001:5432"

mariadb:
  ...
  ports:
    - "8002:3306"
```

이렇게만 수정하면 됩니다.
내부 포트(5432, 3306)는 그대로 유지하고, 외부에서 사용하는 포트만 원하는 번호로 바꾸면 됩니다.[^2_4][^2_5]

***

### 3. 방화벽/보안 팁 (외부 접속용)

우분투 서버에서:

```bash
# 예: PostgreSQL 외부 포트 5433 허용
sudo ufw allow 5433/tcp

# 예: MariaDB 외부 포트 3307 허용
sudo ufw allow 3307/tcp

# HTTPS 443 (nginx/Let's Encrypt) 허용
sudo ufw allow 443/tcp
```

또는 Cloud Provider(예: AWS, GCP) 방화벽/Security Group에서 `5433`, `3307`를 허용해 주어야 합니다.[^2_6][^2_7]

***

### 4. 응용: “외부 접속용” vs “내부 서비스용” 포트 분리

- 외부에서 직접 접속:
    - `5433(→PostgreSQL)`, `3307(→MariaDB)`
    - 예: 개발자 PC에서 PGAdmin, Navicat 등으로 접속.
- 내부 서비스(예: Django, Node.js 등)에서 DB 사용:
    - Docker 내부 네트워크에서 `postgres:5432`, `mariadb:3306`으로만 사용.
    - 외부 포트 노출은 관리용만, 어플리케이션은 내부 포트 사용 → 보안 강화.[^2_8][^2_9]

***

원하시면 다음 단계로:

- `docker-compose-db.yml`을 **외부 포트만 노출/HTTPS 방화벽 포함**으로 더 세분화한 예시를
- “외부 포트 표”(예: 5432 → 5433, 3306 → 3307)와 같이 정리해 드리겠습니다.
<span style="display:none">[^2_10][^2_11][^2_12][^2_13][^2_14][^2_15]</span>

<div align="center">⁂</div>

[^2_1]: https://stackoverflow.com/questions/37775702/changing-a-postgres-containers-server-port-in-docker-compose

[^2_2]: https://stackoverflow.com/questions/52567272/docker-compose-postgres-expose-port/52567886

[^2_3]: https://stackoverflow.com/questions/56212960/how-to-configure-mariadb-docker-compose-file-to-use-other-port-than-3306

[^2_4]: https://www.geeksforgeeks.org/devops/change-postgresql-container-port-in-docker-compose/

[^2_5]: https://www.youtube.com/watch?v=1AqHJg55h1Q

[^2_6]: https://docs.docker.com/get-started/docker-concepts/running-containers/publishing-ports/

[^2_7]: https://cori.tistory.com/361

[^2_8]: https://www.youtube.com/watch?v=Yn0C8CQu4ww

[^2_9]: https://stackoverflow.com/questions/31249112/allow-docker-container-to-connect-to-a-local-host-postgres-database

[^2_10]: https://elixirforum.com/t/connecting-to-postgres-in-docker-compose/65974

[^2_11]: https://stackoverflow.com/questions/77791697/how-to-expose-mariadb-container-port-outside-of-the-docker-networking

[^2_12]: https://www.reddit.com/r/docker/comments/qkpe0l/how_to_set_mariadb_server_with_same_port_exposed/

[^2_13]: https://www.w3resource.com/PostgreSQL/snippets/connect-postgresql-docker-outside.php

[^2_14]: https://forums.docker.com/t/docker-exposed-ports-are-not-accessible-from-all-remote-networks/147951

[^2_15]: https://graykang.tistory.com/entry/dockermariadb-설치-설정외부-접속-허용-docker-composeyml


---

# docker-compose 오류 발생, docker compose 실행 가능, alias 지정이 필요

Ubuntu 22.04/24.04 기준으로, 지금은 **`docker compose` (공백)** 가 공식이며, **`docker-compose` (하이픈)** 명령은 기본으로 안 깔려 있는 상태입니다.[^3_1][^3_2][^3_3]
기존 문서/스크립트가 `docker-compose`를 쓰고 있어 오류가 난 것이고, 이를 **alias나 래퍼 스크립트**로 해결할 수 있습니다.[^3_4][^3_5]

***

## 1. 지금 상태 확인

터미널에서 순서대로 실행해 보세요.

```bash
docker --version
docker compose version
docker-compose --version
```

- `docker` / `docker compose` 는 정상,
- `docker-compose` 는 `command not found` 나면, 아래 방법 중 하나로 해결합니다.[^3_2][^3_6]

***

## 2. 간단 alias (현재 셸에서만)

일단 당장만 쓰고 싶으면:

```bash
alias docker-compose="docker compose"
```

- 이 상태에서 `docker-compose -f docker-compose-db.yml up -d` 처럼 사용 가능.
- 단, **현재 터미널 세션에서만** 유효합니다 (새 터미널 열면 사라짐).[^3_5]

***

## 3. 영구 alias (로그인할 때마다 자동 적용)

`bash` 기준 (`~/.bashrc` 또는 `~/.bash_profile`):

```bash
echo 'alias docker-compose="docker compose"' >> ~/.bashrc
source ~/.bashrc
```

`zsh` 사용이면:

```bash
echo 'alias docker-compose="docker compose"' >> ~/.zshrc
source ~/.zshrc
```

이제 새 터미널을 열어도 `docker-compose` 명령이 `docker compose`로 동작합니다.[^3_7][^3_5]

***

## 4. 시스템 전체에서 동작하게 (스크립트 파일 생성 – 권장)

스크립트 하나 만들어 두면, **makefile / 스크립트 / cron 등**에서도 `docker-compose`가 잘 동작합니다.[^3_4][^3_5]

```bash
# 1) 래퍼 스크립트 생성
sudo tee /usr/local/bin/docker-compose >/dev/null << 'EOF'
#!/usr/bin/env bash
docker compose "$@"
EOF

# 2) 실행 권한 부여
sudo chmod +x /usr/local/bin/docker-compose

# 3) 확인
docker-compose version
```

- 이제 어떤 곳에서든 `docker-compose` 실행 시 내부적으로 `docker compose`가 호출됩니다.[^3_5][^3_4]
- 예:
    - `docker-compose -f docker-compose-db.yml up -d`
    - `docker-compose -f docker-compose-ide.yml down`

***

## 5. 기존 문서 수정 vs 호환 유지

선택지는 두 가지입니다.

1. **문서/스크립트를 전부 `docker compose` 로 바꾼다**
    - 가장 깔끔한 방법.
    - 예: `docker-compose -f docker-compose-db.yml up -d` → `docker compose -f docker-compose-db.yml up -d`.
2. **위 4번처럼 `/usr/local/bin/docker-compose` 래퍼를 만들어서 하위호환 유지**
    - 기존 문서/튜토리얼 그대로 사용 가능.
    - 팀 내 환경에서도 “`docker compose`만 설치해 두면 된다”는 규칙으로 맞추기 좋음.[^3_1][^3_4]

***

## 6. 권장 드리는 설정 (정리)

당장 편하게 쓰려면:

```bash
sudo tee /usr/local/bin/docker-compose >/dev/null << 'EOF'
#!/usr/bin/env bash
docker compose "$@"
EOF
sudo chmod +x /usr/local/bin/docker-compose
```

그리고 평소에는 문서/명령을 천천히 `docker compose` 형태로 바꿔 나가시면 됩니다.[^3_4][^3_5]

혹시 지금 발생한 **정확한 에러 메시지**(`docker-compose: command not found`인지, 다른 에러인지)도 알려주시면, 그에 맞춰 추가로 점검할 부분(예: PATH, 플러그인 설치 여부 등)을 짚어 드리겠습니다.
<span style="display:none">[^3_10][^3_11][^3_12][^3_13][^3_14][^3_15][^3_8][^3_9]</span>

<div align="center">⁂</div>

[^3_1]: https://forums.docker.com/t/docker-compose-vs-docker-compose/137884

[^3_2]: https://github.com/orgs/community/discussions/116610

[^3_3]: https://kodekloud.com/blog/docker-compose-command-not-found/

[^3_4]: https://stackoverflow.com/questions/72099653/how-to-alias-docker-compose-to-docker-compose/72187587

[^3_5]: https://stackoverflow.com/questions/72099653/how-to-alias-docker-compose-to-docker-compose

[^3_6]: https://www.baeldung.com/ops/docker-compose-not-found

[^3_7]: https://shinjam.tistory.com/entry/docker-compose-VS-docker-compose

[^3_8]: https://stackoverflow.com/questions/66514436/difference-between-docker-compose-and-docker-compose

[^3_9]: https://seosh817.tistory.com/387

[^3_10]: https://www.reddit.com/r/docker/comments/vjndfd/install_dockercompose_v1_in_ubuntu_2204_lts/

[^3_11]: https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-compose-on-ubuntu-22-04

[^3_12]: https://www.reddit.com/r/docker/comments/uzng7t/please_help_a_newbie_dockercompose_vs_docker/

[^3_13]: https://blog.naver.com/PostView.naver?blogId=mdc1020\&logNo=222975987341

[^3_14]: https://www.reddit.com/r/docker/comments/12ayhn0/docker_compose_vs_dockercompose/

[^3_15]: https://god-logger.tistory.com/117


---

# error EACCES: permission denied, mkdir '/home/coder/.config/code-server

`error EACCES: permission denied, mkdir '/home/coder/.config/code-server'`는 **code‑server 컨테이너가 마운트한 디렉토리에 `coder` 유저가 쓰기 권한이 없어서** 발생하는典型한 permission 문제입니다.[^4_1][^4_2][^4_3]

***

### 원인 요약

지금 `docker-compose-ide.yml`에서 대략 이런 식으로 마운트해 둔 것 같습니다:

```yaml
volumes:
  - ./config-code/.config:/home/coder/.config
  - ./config-code/.local:/home/coder/.local
```

- 호스트(`./config-code/.config`) 디렉토리 소유/권한이 `coder` 유저가 아닌 경우,
- 컨테이너 안에서 `coder`로 돌아가는 code‑server가 `mkdir /home/coder/.config/code-server`를 시도하다가 **EACCES**가 뜹니다.[^4_3][^4_4][^4_1]

***

## 1. 해결 방법 1: 호스트 디렉토리를 올바른 권한으로 맞추기

### 1‑1. 호스트 디렉토리 생성 및 권한 설정

```bash
# 1) 디렉토리 구조 미리 생성
mkdir -p ~/labs/ide/config-code/.config
mkdir -p ~/labs/ide/config-code/.local

# 2) 현재 사용자 UID/GID 확인
id -u     # 예: 1000
id -g     # 예: 1000

# 3) 디렉토리 소유권을 현재 사용자로 맞추기
sudo chown -R $(id -u):$(id -g) ~/labs/ide/config-code/
```

- 그러면 컨테이너 내부의 `coder` 유저가 마운트된 디렉토리를 쓸 수 있습니다.[^4_1][^4_3]


### 1‑2. `docker-compose-ide.yml` 보완 (권장)

```yaml
code-server:
  image: codercom/code-server:latest
  restart: unless-stopped
  ports:
    - "3091:8080"
  volumes:
    - ./projects:/home/coder/project
    - ./config-code/.config:/home/coder/.config
    - ./config-code/.local:/home/coder/.local
  environment:
    PASSWORD: "your-codeserver-password"
  user: "$(id -u):$(id -g)"
```

- `user: "$(id -u):$(id -g)"` 덕분에 컨테이너 내부 `coder` 유저가 마운트된 디렉토리를 같은 UID/GID로 접근해 권한 오류를 피합니다.[^4_5][^4_3]

***

## 2. 해결 방법 2: 호스트 디렉토리를 pre‑chmod 해 주기 (NFS/권한 제한 환경)

만약 `chown`이 안 되는 환경(예: NFS, root가 아닌 공유 스토리지)이라면:

```bash
mkdir -p ~/labs/ide/config-code/.config
mkdir -p ~/labs/ide/config-code/.local

chmod -R 755 ~/labs/ide/config-code
# 더 느슨하게는 777 (보안 약화, 테스트용)
chmod -R 777 ~/labs/ide/config-code
```

- `chmod 777`은 편하되, 외부에 노출된 서버라면 가능하면 `755` + `chown` 조합으로 권한을 좁히는 게 좋습니다.[^4_6][^4_7]

***

## 3. 해결 방법 3: 마운트하지 않고 컨테이너 내부 `.config`만 쓰기

만약 “호스트에 config를 저장할 필요가 없다”면, 마운트 구문을 아예 빼고, 처음 실행 시 `coder` 유저가 컨테이너 내부에 `~/.config/code-server`를 자유롭게 만들게 합니다.

```yaml
code-server:
  image: codercom/code-server:latest
  restart: unless-stopped
  ports:
    - "3091:8080"
  volumes:
    - ./projects:/home/coder/project
  environment:
    PASSWORD: "your-codeserver-password"
  # user: ... 생략 가능
```

- 이 경우 `coder` 유저는 컨테이너 내부 `/home/coder/.config`를 그대로 쓰고, **권한 문제는 사라집니다.**
- 다만, 컨테이너가 재생성되면 `~/.config/code-server` 설정이 날아갈 수 있음에 주의.[^4_2][^4_3]

***

## 4. 지금 바로 적용해 볼 수 있는 흐름

1. 터미널에서:
```bash
cd ~/labs/ide
mkdir -p config-code/.config
mkdir -p config-code/.local
sudo chown -R $(id -u):$(id -g) config-code/
```

2. `docker-compose-ide.yml` 열어서 `code-server` 서비스에 `user: "$(id -u):$(id -g)"` 추가.
3. 재시작:
```bash
docker compose -f docker-compose-ide.yml down
docker compose -f docker-compose-ide.yml up -d
```

- 이제 `https://dev.example.com/ide` 접속 시 `error EACCES: mkdir '/home/coder/.config/code-server'`가 더 이상 안 뜨고,
- code‑server가 정상적으로 `~/.config/code-server`를 생성하고 실행됩니다.[^4_8][^4_3][^4_1]

***

원하시면 현재 `docker-compose-ide.yml` 전체 내용을 알려주시면, 해당 파일 기준으로 **정확히 어디에 `chmod` / `chown` / `user: ...`을 넣어야 할지** 라인별로 표시해 드리겠습니다.
<span style="display:none">[^4_10][^4_11][^4_12][^4_13][^4_14][^4_15][^4_16][^4_9]</span>

<div align="center">⁂</div>

[^4_1]: https://github.com/coder/code-server/issues/2234

[^4_2]: https://github.com/coder/code-server/issues/403

[^4_3]: https://github.com/coder/code-server/issues/1188

[^4_4]: https://github.com/coder/code-server/issues/7353

[^4_5]: https://stackoverflow.com/questions/72099653/how-to-alias-docker-compose-to-docker-compose/72187587

[^4_6]: https://stackoverflow.com/questions/66496890/vs-code-nopermissions-filesystemerror-error-eacces-permission-denied

[^4_7]: https://stackoverflow.com/questions/48957195/how-to-fix-docker-permission-denied

[^4_8]: https://github.com/coder/code-server/discussions/2574

[^4_9]: https://github.com/coder/code-server/issues/4166

[^4_10]: https://lightrun.com/answers/coder-code-server-unable-to-start-cdrcode-server-in-docker-container-error-eacces-permission-denied-mkdir-hom

[^4_11]: https://www.reddit.com/r/docker/comments/ww6rt5/eacces_permission_denied/

[^4_12]: https://hobbylists.tistory.com/m/entry/시놀로지-나스에서-Visual-Studio-Code-사용하기Docker-웹-서버/comments

[^4_13]: https://bundw.tistory.com/15

[^4_14]: https://lightrun.com/answers/coder-code-server-running-dockerdocker-compose---cannot-mkdir-permission-denied-eacces

[^4_15]: https://forums.docker.com/t/docker-noob-asking-for-help-eacces-permission-denied-mkdir-home-wiki/119133

[^4_16]: https://stackoverflow.com/questions/66314616/eacces-permission-denied-mkdir-while-trying-to-use-docker-volumes-in-a-node


---

# ✔ Network ssh_default  Created                                                                                      0.1s

✔ Container ssh-ttyd-1 Created                                                                                      0.2s
Attaching to ttyd-1
ttyd-1 exited with code 0 (restarting)
ttyd-1 exited with code 0 (restarting)
ttyd-1 exited with code 0 (restarting)
ttyd-1 exited with code 0 (restarting)
ttyd-1 exited with code 0 (restarting)
ttyd-1 exited with code 0 (restarting)

# docker-compose-ttyd.yml

version: '3.9'

services:
ttyd:
image: tsl0922/ttyd:latest
restart: unless-stopped
ports:
- "50082:7681"  \# 외부:50082 → ttyd:7681
command: bash -l
environment:
- HTTP_USERNAME=tty
- HTTP_PASSWORD="a2026!@\#"
\# - ENABLE_SSL=true   \# 나중에 reverse proxy + SSL을 쓰면 이건 뺀다
volumes:
- /home:/home:ro
- /etc:/etc:r

ttyd 컨테이너가 **`exited with code 0 (restarting)`** 를 반복한다는 것은,
“ttyd가 실행 후 바로 종료되고, `restart: unless-stopped`에 의해 무한 재시작” 상태라는 의미입니다.[^5_1][^5_2]

***

## 1. 가장 흔한 원인

`tsl0922/ttyd`는 기본적으로 **TTY 서버** 역할이라,
`command: bash -l`만 있는 상태에서:

- `bash -l`이 실행되고,
- 콘솔/터미널에 연결된 클라이언트가 없으면 bash가 바로 종료 → ttyd 도 같이 종료 → `exited 0`
- `restart: unless-stopped`라 다시 기동 → 다시 종료 → 반복.[^5_3][^5_1]

***

## 2. 수정된 `docker-compose-ttyd.yml` (정상 동작 버전)

TTY 서버를 **백그라운드에서 계속 실행**하게 하려면:

- `ttyd` 자체가 bash를 자식으로 띄우고,
- bash를 `--login` + `--interactive` 모드로 유지하는 형태가 좋습니다.

```yaml
# docker-compose-ttyd.yml
version: '3.9'

services:
  ttyd:
    image: tsl0922/ttyd:latest
    restart: unless-stopped
    ports:
      - "50082:7681"  # 외부:50082 → ttyd:7681
    # ttyd 명령으로 bash를 직접 실행
    command: ["ttyd", "-c", "tty:YOUR_PASSWORD", "bash", "-l"]
    environment:
      HTTP_USERNAME: "tty"
      HTTP_PASSWORD: "a2026!@#"
    # volumes는 필요 시만
    volumes:
      - /home:/home:ro
      - /etc:/etc:ro
```


### 포인트

- `command: ["ttyd", "-c", "tty:YOUR_PASSWORD", "bash", "-l"]`
    - `ttyd -c tty:YOUR_PASSWORD bash -l`
    - `tty:YOUR_PASSWORD` 부분은 **HTTP 기본 인증이 아니라** “TTY 접속용 패스워드”입니다.
    - 안 쓰려면 `-c` 옵션을 빼도 무방.
- HTTP 기본 인증은 `HTTP_USERNAME` / `HTTP_PASSWORD`로만 처리.[^5_1][^5_3]

***

## 3. 더 간단한 예시 (HTTP 인증 + bash만 실행)

```yaml
command: ["ttyd", "bash", "-l"]
```

- 이런 식으로 하면,
    - HTTP 기본 인증만 `HTTP_USERNAME` / `HTTP_PASSWORD`로,
    - TTY 쪽 패스워드는 안 쓰고,
    - `ttyd`가 `bash -l`을 계속 유지하면서 재시작 안 합니다.[^5_2][^5_1]

***

## 4. 적용해 보기

```bash
# 1) 현재 컨테이너 내리기
docker compose -f docker-compose-ttyd.yml down

# 2) 위 수정한 docker-compose-ttyd.yml로 up
docker compose -f docker-compose-ttyd.yml up -d

# 3) 로그 확인
docker compose -f docker-compose-ttyd.yml logs -f
```

- 이제 `ttyd-1 exited with code 0 (restarting)`가 반복되지 않고,
    - `ttyd-1` 컨테이너가 계속 `Running` 상태로 유지되며,
    - `http://서버IP:50082` 접속 시 웹 터미널이 정상적으로 나옵니다.[^5_2][^5_1]

***

## 5. 옵션/확장

- `ttyd` 옵션으로 `--wss` 또는 `--ssl`을 쓰고 싶으면,
    - 지금처럼 `ENABLE_SSL=true` 보다는
    - `command: ["ttyd", "--ssl", "--ssl-cert", "/ssl/fullchain.pem", "--ssl-key", "/ssl/privkey.pem", "bash", "-l"]`
    - 처럼 명시적으로 준 뒤, `volumes`로 인증서를 마운트하는 방식이 안정적입니다.[^5_1][^5_2]

혹시 `ttyd` 로그에 나오는 **정확한 에러 메시지**가 있다면, 그 내용도 붙여 주시면, 그에 맞춰 더 디테일하게 조정해 드리겠습니다.

<div align="center">⁂</div>

[^5_1]: https://hub.docker.com/r/tsl0922/ttyd

[^5_2]: https://devopslog.tistory.com/172

[^5_3]: https://github.com/Cp0204/ttydBridge

