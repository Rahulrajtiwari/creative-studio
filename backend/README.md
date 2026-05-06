# Creative Studio Backend

## System Architecture and DB Schema
![](../screenshots/creative-studio-architecture.png)
![](../screenshots/creative-studio-db-architecture.png)

The backend follows a **Modular, Feature-Driven Architecture**, heavily inspired by the principles of Hexagonal Architecture (Ports & Adapters).

* **Structure:** Code is organized by feature domain (e.g., /images, /galleries, /users) rather than by technical layer (/controllers, /services).  
* **Rationale:**  
  * **Scalability:** This approach prevents individual directories from becoming unwieldy as the application grows.  
  * **Maintainability:** All code related to a single feature is co-located, making it easier to understand, modify, and test.  
  * **High Cohesion, Low Coupling:** Modules are self-contained and interact through well-defined interfaces (services and DTOs), making the system robust and flexible.

### Technology Stack

| Category           | Technology / Service                                              |
| :----------------- | :---------------------------------------------------------------- |
| **Frontend**       | Angular, TypeScript, Angular Material, Tailwind CSS               |
| **Backend**        | Python, FastAPI, Pydantic                                         |
| **Database**       | Private Cloud SQL (PostgreSQL) via the Cloud SQL Auth Proxy + IAM |
| **Cloud Provider** | Google Cloud Platform (GCP)                                       |
| **Deployment**     | Private GKE (Internal HTTPS LB), Helm chart at `deploy/helm`      |
| **AuthN**          | Generic OIDC (PyJWT + JWKS); IdP-agnostic (Ping/Okta/Entra/etc.)  |
| **AI Models**      | Imagen, Veo, Gemini (via Vertex AI SDK)                           |

## 🚀 Backend Setup

To run the backend locally using Docker Compose, the repository ships a
working `backend/.local.env` file. The minimum overrides you need before the
first run are listed below — see [`../DEVELOPMENT.md`](../DEVELOPMENT.md) for
the full guide and OIDC IdP onboarding steps.

### 1. Configure `backend/.local.env`

```bash
# Application
PROJECT_ID="my-dev-project"
LOG_LEVEL="INFO"
GENMEDIA_BUCKET="my-dev-genmedia"
VIDEO_BUCKET="my-dev-video"
IMAGE_BUCKET="my-dev-image"
SIGNING_SA_EMAIL="cs-development-read@my-dev-project.iam.gserviceaccount.com"

# OIDC (replaces Firebase + Identity Platform)
OIDC_ISSUER="https://login.example.com/idp"
OIDC_AUDIENCES="creative-studio-dev"
OIDC_ALLOWED_EMAIL_DOMAINS="example.com"
OIDC_ALLOWED_GROUPS_CLAIM="groups"
OIDC_ALLOWED_GROUPS=""

# Local Postgres container (provided by docker-compose.yml)
DB_USER="studio_user"
DB_PASS="studio_pass"
DB_NAME="creative_studio"
DB_HOST="postgres"
DB_PORT="5432"
USE_CLOUD_SQL_AUTH_PROXY=false

# Front-end / ingress hardening
BEHIND_INGRESS=false
TRUSTED_HOSTS="localhost,127.0.0.1"
FRONTEND_URL="http://localhost:4200"
```

### 2. Running the Application

We use Docker Compose to run the application locally. Please refer to the [Development Guide](../DEVELOPMENT.md) for detailed instructions on how to start the services.

If you want to start just the backend you can run the following command:

```bash
docker compose up backend
```

## Code Styling & Commit Guidelines

To maintain code quality and consistency:

* **Python (Backend):** We adhere to the [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html), using tools like `pylint` and `black` for linting and formatting.

### Backend (Python with `pylint` and `black`)

1.  **Ensure Dependencies are Installed:**
    Add `pylint` and `black` to your `backend/requirements.txt` file:
    ```
    pylint
    black
    ```
    Then install them within your virtual environment:
    ```bash
    pip install pylint black
    # or pip install -r requirements.txt
    ```
2.  **Configure `pylint`:**
    It's recommended to have a `.pylintrc` file in your `backend/` directory to configure `pylint` rules. You might need to copy a standard one or generate one (`pylint --generate-rcfile > .pylintrc`).
3.  **Check for linting issues with `pylint`:**
    Navigate to the `backend/` directory and run:
    ```bash
    pylint .
    ```
    (Or specify modules/packages: `pylint your_module_name`)
4.  **Format code with `black`:**
    To automatically format all Python files in the current directory and subdirectories:
    ```bash
    python -m black . --line-length=80
    ```



### 🛡️ Automatic Checks with Pre-commit

To guarantee style standards compliance automatically on every commit, we use a fully containerized `pre-commit` setup. Please see the [Development Guide](../DEVELOPMENT.md#5-code-quality--pre-commit-hooks) for installation instructions to link it to your `git commit` hooks.

## 🧪 Running Tests

We use `pytest` for testing and `pytest-cov` for coverage reporting. The project uses `uv` for package management, so tests should be executed within the virtual environment.

> [!IMPORTANT]
> **PR Requirement**: To create and merge Pull Requests, you must achieve at least **80% code coverage** across all `src/` files. The GitHub Actions CI will automatically reject PRs below this threshold.
>
> You can verify this condition locally before pushing by running:
> ```bash
> cd backend
> uv run pytest tests -v --cov=src --cov-fail-under=80
> ```


### 1. Run All Tests
To run all tests together with verbose output:
```bash
cd backend
uv run pytest -v
```

### 2. Run with Coverage
To run all tests and generate a coverage report for ALL files:
```bash
cd backend
uv run pytest -v --cov=src tests/
```
To see a line-by-line missing report, add `--cov-report=term-missing`:
```bash
uv run pytest -v --cov=src tests/ --cov-report=term-missing
```

### 3. Run Specific Component
To run tests for a single component:
```bash
cd backend
uv run pytest tests/users -v
```

### 📋 Notes
- **Async Support**: Async tests are implemented using `@pytest.mark.anyio`.
- **Fixtures**: Global fixtures (e.g., API client, mock database session) are defined in `tests/conftest.py`.
