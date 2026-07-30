from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import quote_plus

from dotenv import load_dotenv
from sqlalchemy import Engine, create_engine


BASE_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = BASE_DIR / ".env"

load_dotenv(ENV_FILE)


def get_database_engine() -> Engine:
    """Create and return a SQLAlchemy engine for HealthPulseAI."""

    server = os.getenv("DB_SERVER")
    database = os.getenv("DB_DATABASE", "HealthPulseAI")
    driver = os.getenv("DB_DRIVER", "ODBC Driver 18 for SQL Server")
    trusted_connection = os.getenv("DB_TRUSTED_CONNECTION", "yes")
    trust_server_certificate = os.getenv(
        "DB_TRUST_SERVER_CERTIFICATE",
        "yes",
    )

    if not server:
        raise ValueError(
            "DB_SERVER is missing. Add it to the .env file."
        )

    connection_string = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"Trusted_Connection={trusted_connection};"
        f"TrustServerCertificate={trust_server_certificate};"
    )

    encoded_connection_string = quote_plus(connection_string)

    engine = create_engine(
        f"mssql+pyodbc:///?odbc_connect={encoded_connection_string}",
        pool_pre_ping=True,
    )

    return engine