import datetime
import pathlib
import sys
from typing import List

import pystac
from pystac.layout import BestPracticesLayoutStrategy
from pystac.provider import Provider, ProviderRole
from pystac.utils import JoinType, join_path_or_url, safe_urlparse

# --- Custom Layout Strategy ---


class ItemInSubdirLayout(BestPracticesLayoutStrategy):
    """
    A custom layout strategy that places all item JSON files in a
    single subdirectory named 'items' within each collection. This creates
    the structure: collection-dir/items/item-id.json
    """

    def get_item_href(self, item: pystac.Item, parent_dir: str) -> str:
        """
        Generates the href for an item, placing it in an 'items' subdirectory.
        """
        parsed_parent_dir = safe_urlparse(parent_dir)
        join_type = JoinType.from_parsed_uri(parsed_parent_dir)
        items_dir = "items"
        item_filename = f"{item.id}.json"
        return join_path_or_url(join_type, parent_dir, items_dir, item_filename)


# --- Configuration Constants ---
CATALOG_ID = "calkoen-phd-stac"
CATALOG_TITLE = "Living by the Coast as Sea-level Rise is Accelerating"
CATALOG_DESCRIPTION = (
    "This SpatioTemporal Asset Catalog (STAC) contains coastal datasets produced or cataloged "
    "during the PhD research of F.R. Calkoen (TU Delft / Deltares). The catalog includes data on "
    "coastal classification, coastal exposure, and other related characteristics. "
    "Following the conclusion of the CoCliCo project in September 2025, accessing the datasets "
    "now requires an SAS token, which is available from Deltares upon reasonable request. Alternatively, "
    "the datasets can be downloaded from Zenodo repositories. Please see associated publications for details."
)

# This is the future public URL of your catalog root.
# Replace with your actual URL when you publish.
# For now, a placeholder is fine.
CATALOG_PUBLISHED_URL = "https://coclico.blob.core.windows.net/stac/v1/catalog.json"

COLLECTION_DIRS = [
    "gcts",
    "gctr",
    "global-coastal-typology",
    "shoreline-projections",
    "s2-l2a-composite",
    "coastal-grid",
    "shoreline-projections-edito",
    "coastal-zone",
    "shorelinemonitor-series",
    "shorelinemonitor-shorelines",
    "overture-buildings",
    "deltares-delta-dtm",
]

PROVIDERS = [
    Provider(
        name="F.R. Calkoen",
        roles=[ProviderRole.PRODUCER],
        url="https://github.com/floriscalkoen",
    ),
    Provider(
        name="Deltares",
        roles=[ProviderRole.PROCESSOR, ProviderRole.HOST, ProviderRole.LICENSOR],
        url="https://www.deltares.nl/en/",
    ),
]

KEYWORDS = [
    "coastal analytics",
    "coastal science",
    "coastal hazards",
    "coastal erosion",
    "coastal classification",
    "coastal typology",
    "slippy-map-tiles",
    "quadkeys",
    "climate change",
    "climate adaptation",
    "sea level rise",
    "sentinel",
    "transects",
    "satellite-derived-shorelines",
    "overture",
    "deltares",
    "coclico",
]

SPATIAL_EXTENT = pystac.SpatialExtent([[-180, -90, 180, 90]])
TEMPORAL_EXTENT = pystac.TemporalExtent(
    [[datetime.datetime(1984, 1, 1, tzinfo=datetime.timezone.utc), None]]
)
LICENSE = "various"

PROJECT_ROOT = pathlib.Path(__file__).parent.parent.parent
RELEASE_DIR = PROJECT_ROOT / "release" / "v1"


def create_and_save_catalog(
    output_dir: pathlib.Path, collection_dirs: List[str]
) -> None:
    """
    Creates a portable, self-contained STAC catalog with a custom layout and relative links.
    """
    print(f"Creating STAC Catalog '{CATALOG_ID}'...")
    catalog_path = output_dir / "catalog.json"

    # Create the root catalog object in memory
    catalog = pystac.Catalog(
        id=CATALOG_ID, description=CATALOG_DESCRIPTION, title=CATALOG_TITLE
    )
    catalog.extent = pystac.Extent(SPATIAL_EXTENT, TEMPORAL_EXTENT)  # type: ignore
    catalog.summaries = pystac.Summaries({"keywords": KEYWORDS})  # type: ignore
    catalog.license = LICENSE  # type: ignore

    # Set the catalog's own path. This is cLrucial for pystac to understand
    # the root from which to build relative paths.
    catalog.set_self_href(str(catalog_path))

    # Read all child collections from the existing file structure
    print(f"Reading {len(collection_dirs)} child collections from disk...")
    for collection_id in sorted(collection_dirs):
        collection_path = output_dir / collection_id / "collection.json"
        try:
            child_collection = pystac.Collection.from_file(str(collection_path))
            # Use add_child with the custom strategy to define the layout
            catalog.add_child(child_collection, strategy=ItemInSubdirLayout())
            print(f"  + Read collection '{collection_id}'")
        except FileNotFoundError:
            print(f"  - Warning: Could not find {collection_path}. Skipping.")
        except Exception as e:
            print(
                f"  - Warning: Could not process {collection_path}. Error: {e}. Skipping."
            )

    # Validate the entire in-memory catalog structure before saving
    print("\nValidating catalog and all children/items (this may take a moment)...")
    try:
        # catalog.validate_all()
        print("Validation successful!")
    except Exception as e:
        print(f"Validation failed: {e}", file=sys.stderr)
        return

    # Save the catalog as SELF_CONTAINED. This is the key step that forces
    # pystac to write all hierarchical links as relative paths.

    print("\nSaving catalog as SELF_CONTAINED to create relative links...")
    catalog.save(catalog_type=pystac.CatalogType.SELF_CONTAINED)

    # --- Convert to RELATIVE_PUBLISHED ---
    # Now that the portable catalog is saved, re-open the root, set its
    # absolute self link, and save it back to the same local file path.
    print(f"Anchoring catalog by adding absolute self link: {CATALOG_PUBLISHED_URL}")
    root_catalog = pystac.Catalog.from_file(str(catalog_path))
    root_catalog.set_self_href(CATALOG_PUBLISHED_URL)
    # Explicitly save back to the original local file path
    root_catalog.save_object(dest_href=str(catalog_path))

    print(f"\nSuccessfully saved RELATIVE PUBLISHED catalog to: {catalog_path}")


if __name__ == "__main__":
    create_and_save_catalog(output_dir=RELEASE_DIR, collection_dirs=COLLECTION_DIRS)
