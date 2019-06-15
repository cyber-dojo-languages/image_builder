#!/bin/bash
set -e

readonly MY_DIR="$( cd "$( dirname "${0}" )" && pwd )"

"${MY_DIR}/dockerfile_augmenter/sh/build_image.sh"
"${MY_DIR}/image_namer/sh/build_image.sh"
"${MY_DIR}/dependents_notifier/sh/build_image.sh"
