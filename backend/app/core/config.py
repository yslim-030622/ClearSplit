from functools import lru_cache
from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


ALLOWED_ENVS = {"local", "test", "staging", "production"}


class Settings(BaseSettings):
    env: str = Field(..., alias="ENV")
    database_url: SecretStr = Field(..., alias="DATABASE_URL")
    jwt_secret: SecretStr = Field(..., alias="JWT_SECRET")
    jwt_algorithm: str = Field(default="HS256", alias="JWT_ALGORITHM")
    access_token_expire_minutes: int = Field(default=15, alias="ACCESS_TOKEN_EXPIRE_MINUTES")
    refresh_token_expire_days: int = Field(default=30, alias="REFRESH_TOKEN_EXPIRE_DAYS")
    cors_origins: str = Field(default="", alias="CORS_ORIGINS")
    trust_proxy_headers: bool = Field(default=False, alias="TRUST_PROXY_HEADERS")
    trusted_proxy_ips: str = Field(default="", alias="TRUSTED_PROXY_IPS")
    rate_limit_max_keys: int = Field(default=10000, alias="RATE_LIMIT_MAX_KEYS")

    # Database connection pool tuning
    db_pool_size: int = Field(default=10, alias="DB_POOL_SIZE")
    db_max_overflow: int = Field(default=20, alias="DB_MAX_OVERFLOW")
    db_pool_timeout_seconds: int = Field(default=30, alias="DB_POOL_TIMEOUT_SECONDS")
    db_pool_recycle_seconds: int = Field(default=1800, alias="DB_POOL_RECYCLE_SECONDS")
    db_connect_timeout_seconds: float = Field(default=10.0, alias="DB_CONNECT_TIMEOUT_SECONDS")

    # S3 Configuration
    aws_region: str = Field(default="us-east-2", alias="AWS_REGION")
    aws_access_key_id: str = Field(default="", alias="AWS_ACCESS_KEY_ID")
    aws_secret_access_key: SecretStr = Field(default=SecretStr(""), alias="AWS_SECRET_ACCESS_KEY")
    s3_bucket_name: str = Field(..., alias="S3_BUCKET_NAME")
    s3_presigned_get_expire_seconds: int = Field(default=900, alias="S3_PRESIGNED_GET_EXPIRE_SECONDS")
    s3_prefix: str = Field(default="receipts", alias="S3_PREFIX")
    max_receipt_bytes: int = Field(default=10485760, alias="MAX_RECEIPT_BYTES")
    max_receipt_pixels: int = Field(default=25000000, alias="MAX_RECEIPT_PIXELS")
    max_ocr_concurrency: int = Field(default=2, alias="MAX_OCR_CONCURRENCY")

    model_config = SettingsConfigDict(
        env_file=(".env", ".env.local", "../.env", "../.env.local"),
        case_sensitive=False,
        extra="ignore",  # Ignore extra fields in .env that aren't in Settings
    )

    @field_validator("env")
    @classmethod
    def validate_env(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in ALLOWED_ENVS:
            allowed = ", ".join(sorted(ALLOWED_ENVS))
            raise ValueError(f"ENV must be one of: {allowed}")
        return normalized

    def get_database_url(self) -> str:
        return self.database_url.get_secret_value()

    def get_jwt_secret(self) -> str:
        return self.jwt_secret.get_secret_value()

    def get_aws_access_key_id(self) -> str:
        return self.aws_access_key_id.strip()

    def get_aws_secret_access_key(self) -> str:
        return self.aws_secret_access_key.get_secret_value().strip()

    def get_cors_origins(self) -> list[str]:
        raw = self.cors_origins.strip()
        if not raw:
            return []
        return [origin.strip() for origin in raw.split(",") if origin.strip()]

    def get_trusted_proxy_ips(self) -> list[str]:
        raw = self.trusted_proxy_ips.strip()
        if not raw:
            return []
        return [value.strip() for value in raw.split(",") if value.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[arg-type]
