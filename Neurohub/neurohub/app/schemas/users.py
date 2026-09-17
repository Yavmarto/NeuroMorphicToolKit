"""Pydantic schemas for users and authentication in NeuroHub."""

from pydantic import BaseModel, EmailStr


class UserBase(BaseModel):
    """Base schema for a user."""

    username: str
    email: EmailStr
    full_name: str | None = None


class UserCreate(UserBase):
    """Schema for creating a new user."""

    password: str


class User(UserBase):
    """Schema for a user (response)."""

    id: str
    is_active: bool
    is_admin: bool

    model_config = {"from_attributes": True}


class Token(BaseModel):
    """Schema for an authentication token."""

    access_token: str
    refresh_token: str | None = None
    token_type: str


class TokenData(BaseModel):
    """Schema for token payload data."""

    username: str | None = None
