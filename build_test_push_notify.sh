#!/bin/bash
set -e

# - - - - - - - - - - - - - - - - - - - - - - - - - - -
# This script is curl'd and run in CircleCI scripts. It
#   o) builds a cyber-dojo-language image
#   o) tests it
#   o) pushes it to dockerhub
#   o) notifies any dependent CircleCI projects
# - - - - - - - - - - - - - - - - - - - - - - - - - - -

readonly MY_NAME=$(basename $0)
readonly MY_DIR="$( cd "$( dirname "${0}" )" && pwd )"
readonly SRC_DIR=${1:-${PWD}}
readonly TMP_DIR=$(mktemp -d /tmp/XXXXXX)

remove_tmp_dir()
{
  rm -rf "${TMP_DIR}" > /dev/null;
}

trap remove_tmp_dir INT EXIT

# - - - - - - - - - - - - - - - - - -

check_use()
{
  if [ "${1}" = '-h' ] || [ "${1}" = '--help' ]; then
    show_use_long
    exit 0
  fi
  if [ ! -d "${SRC_DIR}" ]; then
    show_use_short
    echo "error: ${SRC_DIR} does not exist"
    exit 3
  fi
  if [ ! -f "${SRC_DIR}/docker/Dockerfile.base" ]; then
    show_use_short
    echo "error: ${SRC_DIR}/docker/Dockerfile.base does not exist"
    exit 3
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - -

show_use_short()
{
  echo "Use: ${MY_NAME} [SRC_DIR|-h|--help]"
  echo ''
  echo '  SRC_DIR defaults to ${PWD}'
  echo '  SRC_DIR/docker/Dockerfile.base must exist'
  echo ''
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - -

show_use_long()
{
  show_use_short
  echo 'Attempts to build a docker-image from ${SRC_DIR}/docker/Dockerfile.base'
  echo "adjusted to fulfil the runner service's requirements."
  echo 'If ${SRC_DIR}/start_point/manifest.json exists the name of the docker-image'
  echo 'will be taken from it, otherwise from ${SRC_DIR}/docker/image_name.json'
  echo
  echo 'If ${SRC_DIR}/start_point/ exists:'
  echo '  1. Attempts to build a start-point image from the git-cloneable ${SRC_DIR}.'
  echo '     $ cyber-dojo start-point create ... --languages ${SRC_DIR}'
  echo '  2. Verifies the red->amber->green starting files progression'
  echo '     o) the starting-files give a red traffic-light'
  echo '     o) with an introduced syntax error, give an amber traffic-light'
  echo "     o) with '6 * 9' replaced by '6 * 7', give a green traffic-light"
  echo
}

#- - - - - - - - - - - - - - - - - - - - - - -

script_path()
{
  local -r script_name=cyber-dojo
  # Run locally when offline
  local -r local_path="${MY_DIR}/../../cyber-dojo/commander/${script_name}"
  local -r curled_path="${TMP_DIR}/${script_name}"

  if on_CI && [ ! -f "${curled_path}" ]; then
    local -r github_org=https://raw.githubusercontent.com/cyber-dojo
    local -r repo_name=commander
    local -r url="${github_org}/${repo_name}/master/${script_name}"
    curl --silent --fail "${url}" > "${curled_path}"
    chmod 700 "${curled_path}"
    echo "${curled_path}"
  elif on_CI && [ -f "${curled_path}" ]; then
    echo "${curled_path}"
  elif [ -f "${local_path}" ]; then
    local -r env_var=COMMANDER_IMAGE=cyberdojo/commander:latest
    echo "${env_var} ${local_path}"
  else
    >&2 echo 'FAILED: Not a CI/CD run so expecting cyber-dojo script in dir at:'
    >&2 echo "${MY_DIR}/../../cyber-dojo/commander"
    exit 3
  fi
}

#- - - - - - - - - - - - - - - - - - - - - - -

src_dir_abs()
{
  # docker volume-mounts cannot be relative
  echo $(cd ${SRC_DIR} && pwd)
}

#- - - - - - - - - - - - - - - - - - - - - - -

image_name()
{
  docker run \
    --rm \
    --volume "$(src_dir_abs):/data:ro" \
    cyberdojofoundation/image_namer
}

#- - - - - - - - - - - - - - - - - - - - - - -

build_image()
{
  # Create new Dockerfile containing extra
  # commands to fulfil the runner's requirements.
  cat "$(src_dir_abs)/docker/Dockerfile.base" \
    | \
      docker run \
        --interactive \
        --rm \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        cyberdojofoundation/image_dockerfile_augmenter \
    > \
      "$(src_dir_abs)/docker/Dockerfile"

  # Write new Dockerfile to stdout in case of debugging
  cat "$(src_dir_abs)/docker/Dockerfile"

  # Build the augmented docker-image.
  docker build \
    --file "$(src_dir_abs)/docker/Dockerfile" \
    --tag "$(image_name)" \
    "$(src_dir_abs)/docker"
}

# - - - - - - - - - - - - - - - - - -

dependent_projects()
{
  docker run \
    --rm \
    --volume "$(src_dir_abs):/data:ro" \
      cyberdojofoundation/image_dependents
}

# - - - - - - - - - - - - - - - - - -

notify_dependent_projects()
{
  echo 'Notifying dependent projects'
  local -r repos=$(dependent_projects)
  docker run \
    --env CIRCLE_API_MACHINE_USER_TOKEN \
    --rm \
      cyberdojofoundation/image_notifier \
        ${repos}
  echo 'Successfully notified dependent projects'
}

# - - - - - - - - - - - - - - - - - -

on_CI()
{
  [ -n "${CIRCLE_SHA1}" ] || [ -n "${TRAVIS}" ]
}

# - - - - - - - - - - - - - - - - - -

testing_myself()
{
  # Don't push CDL images or notify dependent repos
  # if building CDL images as part of image_builder's own tests.
  [ "${CIRCLE_PROJECT_REPONAME}" = 'image_builder' ]
}

# - - - - - - - - - - - - - - - - - -

create_cdl_docker_image()
{
  echo "Building docker-image $(image_name)"
  build_image
}

# - - - - - - - - - - - - - - - - - -

has_start_point()
{
  [ -d "$(src_dir_abs)/start_point" ]
}

start_point_image_name()
{
  echo test_start_point_image
}

create_start_point_image()
{
  local -r name=$(start_point_image_name)
  echo "Building ${name}"
  eval $(script_path) start-point create "${name}" --languages "$(src_dir_abs)"
}

remove_start_point_image()
{
  docker image rm $(start_point_image_name) > /dev/null
}

# - - - - - - - - - - - - - - - - - -

check_red_amber_green()
{
  local -r name=$(start_point_image_name)
  echo 'Checking red->amber->green progression (TODO)'
  #...TODO (will use cyber-dojo-languages/image_hiker/check_red_amber_green.rb
}

# - - - - - - - - - - - - - - - - - -

check_version()
{
  "${SRC_DIR}/check_version.sh"
}

# - - - - - - - - - - - - - - - - - -

push_cdl_image_to_dockerhub()
{
  echo "Pushing $(image_name) to dockerhub"
  docker push $(image_name)
  echo "Successfully pushed $(image_name) to dockerhub"
}

# - - - - - - - - - - - - - - - - - -

check_use $*
create_cdl_docker_image
if has_start_point; then
  create_start_point_image
  check_red_amber_green
  remove_start_point_image
else
  check_version
fi
if on_CI && ! testing_myself; then
  push_cdl_image_to_dockerhub
  notify_dependent_projects
fi
echo
