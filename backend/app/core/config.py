from functools import lru_cache
from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    env: str = Field("local", alias="ENV")
    database_url: SecretStr = Field(..., alias="DATABASE_URL")
    jwt_secret: SecretStr = Field(..., alias="JWT_SECRET")
    jwt_algorithm: str = Field(default="HS256", alias="JWT_ALGORITHM")
    access_token_expire_minutes: int = Field(default=15, alias="ACCESS_TOKEN_EXPIRE_MINUTES")
    refresh_token_expire_days: int = Field(default=30, alias="REFRESH_TOKEN_EXPIRE_DAYS")
    cors_origins: str = Field(default="", alias="CORS_ORIGINS")
    trust_proxy_headers: bool = Field(default=False, alias="TRUST_PROXY_HEADERS")
    trusted_proxy_ips: str = Field(default="", alias="TRUSTED_PROXY_IPS")
    rate_limit_max_keys: int = Field(default=10000, alias="RATE_LIMIT_MAX_KEYS")
    
    # S3 Configuration
    aws_region: str = Field(default="us-east-2", alias="AWS_REGION")
    s3_bucket_name: str = Field(..., alias="S3_BUCKET_NAME")
    s3_presigned_get_expire_seconds: int = Field(default=900, alias="S3_PRESIGNED_GET_EXPIRE_SECONDS")
    s3_prefix: str = Field(default="receipts", alias="S3_PREFIX")
    max_receipt_bytes: int = Field(default=10485760, alias="MAX_RECEIPT_BYTES")
    max_receipt_pixels: int = Field(default=25000000, alias="MAX_RECEIPT_PIXELS")
    max_ocr_concurrency: int = Field(default=2, alias="MAX_OCR_CONCURRENCY")

    model_config = SettingsConfigDict(
        env_file=(".env", "../.env"),
        case_sensitive=False,
        extra="ignore",  # Ignore extra fields in .env that aren't in Settings
    )

    def get_database_url(self) -> str:
        return self.database_url.get_secret_value()

    def get_jwt_secret(self) -> str:
        return self.jwt_secret.get_secret_value()

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
