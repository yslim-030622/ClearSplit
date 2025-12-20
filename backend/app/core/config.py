"""Application configuration with secure secret handling.

SECURITY NOTICE:
- Never hardcode secrets in this file
- All sensitive values MUST come from environment variables
- Use SecretStr for passwords/tokens to prevent accidental logging
- In production (ENV=production), missing secrets cause startup failure
"""

import sys
from functools import lru_cache
from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables.
    
    Required Environment Variables:
    - DATABASE_URL: PostgreSQL connection string
    - JWT_SECRET: Secret key for JWT token signing (use: openssl rand -hex 32)
    
    Optional (with defaults):
    - ENV: Environment name (local|test|production) [default: local]
    - JWT_ALGORITHM: JWT algorithm [default: HS256]
    - ACCESS_TOKEN_EXPIRE_MINUTES: Access token lifetime [default: 15]
    - REFRESH_TOKEN_EXPIRE_DAYS: Refresh token lifetime [default: 30]
    """
    
    env: str = Field("local", alias="ENV", description="Environment: local, test, or production")
    database_url: SecretStr = Field(..., alias="DATABASE_URL", description="PostgreSQL connection string")
    jwt_secret: SecretStr = Field(..., alias="JWT_SECRET", description="Secret key for JWT signing")
    jwt_algorithm: str = Field(default="HS256", alias="JWT_ALGORITHM")
    access_token_expire_minutes: int = Field(
        default=15, 
        alias="ACCESS_TOKEN_EXPIRE_MINUTES",
        ge=1,
        description="Access token expiration in minutes"
    )
    refresh_token_expire_days: int = Field(
        default=30, 
        alias="REFRESH_TOKEN_EXPIRE_DAYS",
        ge=1,
        description="Refresh token expiration in days"
    )

    model_config = SettingsConfigDict(
        env_file=(".env", ".env.local", "../.env"),
        case_sensitive=False,
        extra="ignore",  # Ignore extra fields in .env that aren't in Settings
    )
    
    @field_validator("jwt_secret")
    @classmethod
    def validate_jwt_secret(cls, v: SecretStr, info) -> SecretStr:
        """Validate JWT secret is strong enough."""
        secret = v.get_secret_value()
        if len(secret) < 32:
            raise ValueError(
                "JWT_SECRET must be at least 32 characters long. "
                "Generate with: openssl rand -hex 32"
            )
        # Only check for weak secrets in production
        env = info.data.get("env", "local")
        if env == "production":
            if secret in ("changeme", "secret", "test-secret", "your-secret-key-here"):
                raise ValueError(
                    "Weak JWT_SECRET detected! Use a strong random secret in production."
                )
        return v
    
    @field_validator("database_url")
    @classmethod
    def validate_database_url(cls, v: SecretStr) -> SecretStr:
        """Validate database URL format."""
        url = v.get_secret_value()
        if not url.startswith(("postgresql://", "postgresql+asyncpg://")):
            raise ValueError(
                "DATABASE_URL must start with 'postgresql://' or 'postgresql+asyncpg://'"
            )
        return v
    
    def get_database_url(self) -> str:
        """Get database URL as plain string (for SQLAlchemy)."""
        return self.database_url.get_secret_value()
    
    def get_jwt_secret(self) -> str:
        """Get JWT secret as plain string (for jose/jwt)."""
        return self.jwt_secret.get_secret_value()


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance.
    
    Raises:
        ValueError: If required secrets are missing or invalid
        SystemExit: In production mode with missing/weak secrets
    """
    try:
        settings = Settings()  # type: ignore[call-arg]
        
        # Fail fast in production with clear error message
        if settings.env == "production":
            # Additional production validations
            secret_val = settings.jwt_secret.get_secret_value()
            if len(secret_val) < 64:
                print(
                    "WARNING: JWT_SECRET is shorter than recommended 64 characters for production",
                    file=sys.stderr
                )
        
        return settings
    
    except Exception as e:
        print(f"❌ Configuration Error: {e}", file=sys.stderr)
        print("\n" + "="*60, file=sys.stderr)
        print("REQUIRED ENVIRONMENT VARIABLES:", file=sys.stderr)
        print("  DATABASE_URL - PostgreSQL connection string", file=sys.stderr)
        print("  JWT_SECRET   - Secret key (generate with: openssl rand -hex 32)", file=sys.stderr)
        print("\nOptional (with defaults):", file=sys.stderr)
        print("  ENV=local", file=sys.stderr)
        print("  JWT_ALGORITHM=HS256", file=sys.stderr)
        print("  ACCESS_TOKEN_EXPIRE_MINUTES=15", file=sys.stderr)
        print("  REFRESH_TOKEN_EXPIRE_DAYS=30", file=sys.stderr)
        print("="*60 + "\n", file=sys.stderr)
        
        # Re-raise the exception for all environments
        raise
