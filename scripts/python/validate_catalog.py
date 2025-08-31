import argparse
import sys

from pystac import Catalog
from pystac.validation import validate_all


def main():
    """
    CLI tool to validate a STAC Catalog.
    """
    parser = argparse.ArgumentParser(description="Validate a STAC catalog.")
    parser.add_argument(
        "catalog_path",
        type=str,
        help="Path to the root catalog.json file to validate.",
    )
    args = parser.parse_args()

    try:
        print(f"Attempting to read catalog from: {args.catalog_path}")
        # Set the root for resolving relative hrefs
        root_catalog = Catalog.from_file(args.catalog_path)

        print(f"Successfully read catalog '{root_catalog.id}'.")
        print("Starting recursive validation of all collections and items...")

        # Validate the entire catalog recursively
        validate_all(root_catalog)

        print("\nValidation successful!")
        print("The STAC catalog and all its children are valid.")
        sys.exit(0)

    except Exception as e:
        print("\nValidation failed.", file=sys.stderr)
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
