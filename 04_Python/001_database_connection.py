from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from config.database import get_database_engine


def test_database_connection() -> None:
    """Test the SQL Server connection."""

    try:
        engine = get_database_engine()

        with engine.connect() as connection:
            result = connection.execute(
                text(
                    """
                    SELECT
                        @@SERVERNAME AS ServerName,
                        DB_NAME() AS DatabaseName,
                        SYSTEM_USER AS ConnectedUser,
                        GETDATE() AS ConnectionTime;
                    """
                )
            )

            row = result.mappings().one()

        print("=" * 60)
        print("HealthPulseAI database connection successful")
        print("=" * 60)
        print(f"Server:       {row['ServerName']}")
        print(f"Database:     {row['DatabaseName']}")
        print(f"Connected as: {row['ConnectedUser']}")
        print(f"Time:         {row['ConnectionTime']}")
        print("=" * 60)

    except SQLAlchemyError as error:
        print("=" * 60)
        print("Database connection failed")
        print("=" * 60)
        print(error)

    except ValueError as error:
        print(error)


if __name__ == "__main__":
    test_database_connection()