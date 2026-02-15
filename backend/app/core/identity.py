"""Normalization helpers for username/email identifiers."""

from __future__ import annotations


def normalize_email(value: str) -> str:
    return value.strip().lower()


def normalize_username(value: str) -> str:
    return value.strip().lower()


def normalize_identifier(value: str) -> str:
    return value.strip().lower()
