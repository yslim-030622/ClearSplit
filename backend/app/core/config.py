from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    env: str = Field("local", alias="ENV")
    database_url: str = Field(..., alias="DATABASE_URL")
    jwt_secret: str = Field(..., alias="JWT_SECRET")
    jwt_algorithm: str = Field(default="HS256", alias="JWT_ALGORITHM")
    access_token_expire_minutes: int = Field(default=15, alias="ACCESS_TOKEN_EXPIRE_MINUTES")
    refresh_token_expire_days: int = Field(default=30, alias="REFRESH_TOKEN_EXPIRE_DAYS")
    
    # S3 Configuration
    aws_region: str = Field(default="us-east-2", alias="AWS_REGION")
    s3_bucket_name: str = Field(..., alias="S3_BUCKET_NAME")
    s3_presigned_get_expire_seconds: int = Field(default=900, alias="S3_PRESIGNED_GET_EXPIRE_SECONDS")
    s3_prefix: str = Field(default="receipts", alias="S3_PREFIX")
    max_receipt_bytes: int = Field(default=10485760, alias="MAX_RECEIPT_BYTES")

    model_config = SettingsConfigDict(
        env_file=(".env", "../.env"),
        case_sensitive=False,
        extra="ignore",  # Ignore extra fields in .env that aren't in Settings
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[arg-type]
