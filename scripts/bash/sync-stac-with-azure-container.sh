#!/bin/bash
az storage blob sync --account-name coclico --source ./release/v1 --container stac/v1
