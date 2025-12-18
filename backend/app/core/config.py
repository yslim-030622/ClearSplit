from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    env: str = Field("local", alias="ENV")
    database_url: str = Field(..., alias="DATABASE_URL")
    jwt_secret: str = Field(..., alias="JWT_SECRET")

    model_config = SettingsConfigDict(env_file=(".env", "../.env"), case_sensitive=False)


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[arg-type]
