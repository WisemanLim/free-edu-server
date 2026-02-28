# Free Education Server (교육용 서버 자동 환경 구축)

이 저장소는 클라우드 혹은 온프레미스 리눅스 서버 상에 교육용 환경(DB 관리, 웹 프로그래밍 IDE, 웹 기반 SSH 터미널)을 단일 스크립트로 쉽고 빠르게 배포하기 위한 환경 스크립트를 제공합니다. 
이를 통해 인프라와 컨테이너에 대한 깊은 지식이 없이도 **안전한 HTTPS 접속** 기반의 통합 교육 환경을 구축할 수 있습니다.

## 주요 기능 (Features)

1. **OS 환경 자동 감지 및 필수 패키지 설치**
   - Ubuntu, Debian 및 CentOS, Rocky 등 다양한 리눅스 배포판을 자동으로 감지합니다.
   - 필수적인 Docker, Docker-compose를 자동으로 설치 또는 확인합니다. (기존 서버 설정 오염 방지)
2. **대화형(Interactive) 설정 프롬프트**
   - 사용자 계정명, 비밀번호, 서비스의 외부 포트 등을 복잡하게 파일을 수정할 필요 없이 스크립트 구동 시 프롬프트를 통해 쉽게 설정하고 기본값을 추천받아 적용할 수 있습니다.
3. **독립적이고 다양한 서비스 스택 (Container 명명 규칙 적용)**
   - **`db` (데이터베이스 환경)**: 외부 노출 포트를 설정할 수 있는 PostgreSQL(`edu_postgres`), MariaDB(`edu_mariadb`) 및 관리툴인 Adminer(`edu_adminer`) 구성.
   - **`ide` (코딩/개발 환경)**: Jupyter Notebook(`edu_jupyter`) / 웹 기반 Code-Server(`edu_code_server`) 환경 구성.
   - **`ssh` (웹 기반 터미널)**: 브라우저만으로 접근할 수 있는 `ttyd`(`edu_ttyd`) 환경 구성.
4. **Dockernized Nginx 자동화 및 SSL/HTTP 호환 지원**
   - 별도의 Host 설치 없이 Docker를 통해 Nginx 환경(`edu_nginx`)을 띄워 여러 서버 포트를 하나의 도메인 혹은 IP 하위 경로로 매핑합니다.
   - Nginx 컨테이너 내부에 Certbot 기능을 함께 내장하여, Host 서버 패키지 설치 없이도 손쉽게 안정적인 HTTPS 환경을 적용할 수 있습니다. 단, 자동입력을 취소하여 기본 HTTP 접속만 허용할 수도 있습니다.

## 시스템 요구사항 (Prerequisites)

- **운영체제**: Ubuntu 22.04/24.04 LTS (권장) 또는 최신 RHEL/CentOS 계열 리눅스.
- **네트워크**: 외부 접속을 위한 퍼블릭 IP와 방화벽 상단 HTTP(80포트) 및 HTTPS(443포트) 개방 필수.
- **도메인**: SSL(HTTPS) 환경 자동 설정을 진행하려는 경우 실제 서버 IP와 연결된 도메인(예 `dev.example.com`)이 필요합니다.

## 디렉토리 구조 (Directory Structure)

```text
free-edu-server/
├── install.sh               # 전체 환경 설치 및 설정 적용을 시작하는 통합 스크립트
├── uninstall.sh             # 컨테이너 서비스 중지 및 Nginx 설정 스크립트를 제거하는 롤백 스크립트
├── db/
│   └── docker-compose-db.yml   # PostgreSQL, MariaDB, Adminer 설정
├── ide/
│   └── docker-compose-ide.yml  # Jupyter, Code-Server 설정
├── ssh/
│   └── docker-compose-ttyd.yml # 웹 기반 ttyd 설정
└── nginx/
    ├── Dockerfile                    # Certbot + Nginx 커스텀 이미지 빌드 파일
    ├── docker-compose-https.yml      # Nginx 컨테이너 구동 명세
    ├── free-edu-server.conf.template # Nginx 리버스 프록시 설정 템플릿
    ├── setup-nginx.sh                # Nginx/Certbot 컨테이너 구동 헬퍼 스크립트
    └── uninstall-nginx.sh            # 구동된 Proxy 컨테이너 및 인증파일 정리용 스크립트
```

## 사용법 (Usage)

### 1단계: 설치 및 배포 구동

해당 깃 저장소를 클론한 후, 스크립트 디렉토리 내에서 설치 스크립트를 실행합니다. 권한이 필요하여 자동으로 `sudo` 명령을 사용하므로, 사용자는 `sudo` 권한을 가진 유저여야 합니다.

```bash
cd free-edu-server
chmod +x install.sh uninstall.sh nginx/*.sh
./install.sh
```

**설치 과정 요약:**
1. **필요 구성요소 설치**: Host 서버 상에는 Docker 및 Docker-Compose만을 설치합니다.
2. **설정값(Prompt) 입력**: 
   - DB환경 (User, Password, Port 등)
   - IDE환경 (Jupyter Token, Code-Server Password, Port 등)
   - SSH환경 (ttyd 웹 로그인 계정/비밀번호, Port 등)
3. **Nginx/SSL 도커 기반 세팅**: 시스템 설정 변경 방지를 위해 Nginx와 Certbot을 Docker 컨테이너로 자체 빌드/실행하여 호스트 서버의 80/443 포트와 통신합니다. (HTTPS의 경우 도메인을 입력하여 연결 진행)
4. **서비스 런칭**: 시작하려는 서비스 모듈 목록(`db`, `ide`, `ssh`, 혹은 `all`)을 물어본 뒤 해당하는 컨테이너를 구동(`docker-compose up -d`) 시켜줍니다.

### 2단계: 서비스 접속

스크립트에서 입력한 도메인 주소(예 `dev.example.com`) 또는 서버의 외부 IP로 다양한 교육 서비스에 접속할 수 있습니다.
(HTTPS 인증서를 성공적으로 발급받았다면 `https://`로 강제되거나 보안상태로 뜨며, 그 외에는 HTTP 연결 `http://`도 정상 동작합니다.)

- **Adminer (DB 관리툴)**: `http(s)://[도메인 또는 IP]/db/`
- **Jupyter Notebook**: `http(s)://[도메인 또는 IP]/jupyter/` (*접속 시 설정한 Token 필요)
- **Code-Server (웹 IDE)**: `http(s)://[도메인 또는 IP]/ide/` (*접속 시 설정한 Password 필요)
- **Web SSH (ttyd)**: `http(s)://[도메인 또는 IP]/tty/` (*HTTP 기본 인증 절차 발생, 설정한 tty 계정 필요)

#### 컨테이너 직접 제어 방법:
내부적으로 컨테이너 이름이 프리픽스 `edu_` 와 함께 고정 관리되므로 로그를 확인할 때 매우 편리합니다.
```bash
docker logs -f edu_code_server
docker restart edu_postgres
```

### 삭제 및 롤백 (Uninstall)

테스트를 완료하거나 환경 설정을 걷어내고 싶을 경우 다음 스크립트를 실행합니다.

```bash
./uninstall.sh
```

- 실행 중인 `db`, `ide`, `ssh` 용 Docker 구동 환경 컨테이너들이 모두 내려갑니다 (`docker-compose down`).
- Nginx 설정용 컨테이너(`edu_nginx`)가 종료되며 발급된 인증서 임시 폴더들이 초기화됩니다.
- *참고: 이 스크립트는 Host 시스템에 설치된 Docker 서비스를 직접 제어하거나 지우지는 않습니다.*
