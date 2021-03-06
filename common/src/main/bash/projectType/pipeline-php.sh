#!/bin/bash

set -o errexit
set -o errtrace
set -o pipefail

export COMPOSER_BIN PHP_BIN
COMPOSER_BIN="${COMPOSER_BIN:-composer}"
PHP_BIN="${PHP_BIN:-php}"
APT_BIN="${APT_BIN:-apt-get}"
ADD_APT_BIN="${ADD_APT_BIN:-add-apt-repository}"
TAR_BIN="${TAR_BIN:-tar}"
CURL_BIN="${CURL_BIN:-curl}"
BINARY_EXTENSION="${BINARY_EXTENSION:-tar.gz}"

# ---- BUILD PHASE ----
function build() {
	downloadComposerIfMissing
	"${COMPOSER_BIN}" install
	local artifactLocation
	local artifactName
	local appName
	appName="$(retrieveAppName)"
	echo "App name retrieved from the project [${appName}]"
	artifactName="${appName}-${PIPELINE_VERSION}.${BINARY_EXTENSION}"
	echo "Artifact name will be [${artifactName}]"
	local tmpDir
	tmpDir="$( mktemp -d )"
	trap "{ rm -rf \$tmpDir; }" EXIT
	artifactLocation="${tmpDir}/${artifactName}"
	echo "Packaging the sources to [${artifactLocation}]"
	"${TAR_BIN}" -czf "${artifactLocation}" .
	local changedGroupId
	# shellcheck disable=SC2005
	changedGroupId="$(echo "$(retrieveGroupId)" | tr . /)"
	local tarSubLocation
	tarSubLocation="${changedGroupId}/${appName}/${PIPELINE_VERSION}/${artifactName}"
	tarSize="$(du -k "${artifactLocation}" | cut -f 1)"
	echo "Uploading the tar with size [${tarSize}] to [${REPO_WITH_BINARIES_FOR_UPLOAD}/${tarSubLocation}] from [${artifactLocation}]"
	local success="false"
	"${CURL_BIN}" -u "${M2_SETTINGS_REPO_USERNAME}:${M2_SETTINGS_REPO_PASSWORD}" -X PUT "${REPO_WITH_BINARIES_FOR_UPLOAD}"/"${tarSubLocation}" --upload-file "${artifactLocation}" --fail && success="true"
	if [[ "${success}" == "true" ]]; then
		echo "File uploaded successfully!"
		return 0
	else
		echo "Failed to upload file!"
		return 1
	fi
}

function downloadAppBinary() {
	local repoWithBinaries="${1}"
	local groupId="${2}"
	local artifactId="${3}"
	local version="${4}"
	local destination
	local changedGroupId
	local pathToArtifact
	destination="$(pwd)/${OUTPUT_FOLDER}/${artifactId}-${version}.${BINARY_EXTENSION}"
	changedGroupId="$(echo "${groupId}" | tr . /)"
	pathToArtifact="${repoWithBinaries}/${changedGroupId}/${artifactId}/${version}/${artifactId}-${version}.${BINARY_EXTENSION}"
	mkdir -p "${OUTPUT_FOLDER}"
	echo "Current folder is [$(pwd)]; Downloading binary from [${pathToArtifact}] to [${destination}]"
	local success="false"
	curl -u "${M2_SETTINGS_REPO_USERNAME}:${M2_SETTINGS_REPO_PASSWORD}" "${pathToArtifact}" -o "${destination}" --fail && success="true"
	local outputDir
	outputDir="${OUTPUT_FOLDER}/${SOURCE_ARTIFACT_TYPE_NAME}"
	mkdir -p "${outputDir}"
	if [[ "${success}" == "true" ]]; then
		echo "File downloaded successfully!"
		"${TAR_BIN}" -zxf "${destination}" -C "${outputDir}"
		echo "File unpacked successfully"
		return 0
	else
		echo "Failed to download file!"
		return 1
	fi
}

function executeApiCompatibilityCheck() {
	downloadComposerIfMissing
	"${COMPOSER_BIN}" test-apicompatibility
}

# TODO: Add to list of required functions
function retrieveGroupId() {
	downloadComposerIfMissing
	"${COMPOSER_BIN}" group-id 2>/dev/null | tail -1
}

# TODO: Add to list of required functions
function retrieveAppName() {
	if [[ "${PROJECT_NAME}" != "" && "${PROJECT_NAME}" != "${DEFAULT_PROJECT_NAME}" ]]; then
		echo "${PROJECT_NAME}"
	else
		downloadComposerIfMissing
		"${COMPOSER_BIN}" app-name 2>/dev/null | tail -1
	fi
}

# ---- TEST PHASE ----

function runSmokeTests() {
	downloadComposerIfMissing
	"${COMPOSER_BIN}" test-smoke
}

# ---- STAGE PHASE ----

function runE2eTests() {
	downloadComposerIfMissing
	"${COMPOSER_BIN}" test-e2e
}

# ---- COMMON ----

function projectType() {
	echo "COMPOSER"
}

function outputFolder() {
	echo "target"
}

function testResultsAntPattern() {
	echo ""
}


# ---- PHP SPECIFIC ----

function downloadComposerIfMissing() {
	installPhpIfMissing
	local composerInstalled
	"${COMPOSER_BIN}" --version > /dev/null 2>&1 && composerInstalled="true" || composerInstalled="false"
	if [[ "${composerInstalled}" == "false" ]]; then
		mkdir -p "$( outputFolder )"
		pushd "$( outputFolder )"  > /dev/null 2>&1
			"${PHP_BIN}" -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"  > /dev/null 2>&1
			"${PHP_BIN}" -r "if (hash_file('SHA384', 'composer-setup.php') === '544e09ee996cdf60ece3804abc52599c22b1f40f4323403c44d44fdfdd586475ca9813a858088ffbc1f233e9b180f061') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"  > /dev/null 2>&1
			"${PHP_BIN}" composer-setup.php  > /dev/null 2>&1
			"${PHP_BIN}" -r "unlink('composer-setup.php');"  > /dev/null 2>&1
			COMPOSER_BIN="$( pwd )/composer.phar"
		popd  > /dev/null 2>&1
	fi
}

function installPhpIfMissing() {
	local phpInstalled
	"${PHP_BIN}" --version > /dev/null 2>&1 && phpInstalled="true" || phpInstalled="false"
	if [[ "${phpInstalled}" == "false" ]]; then
		# LAME
		export LANG=C.UTF-8
		"${APT_BIN}" -y install python-software-properties  > /dev/null 2>&1
		"${ADD_APT_BIN}" -y ppa:ondrej/php  > /dev/null 2>&1
		"${APT_BIN}" -y update && "${APT_BIN}" -y install php7.2  > /dev/null 2>&1
		"${APT_BIN}" -y install php-pear php7.2-curl php7.2-dev php7.2-gd php7.2-mbstring php7.2-zip php7.2-mysql php7.2-xml  > /dev/null 2>&1
	fi
}

export ARTIFACT_TYPE
ARTIFACT_TYPE="${SOURCE_ARTIFACT_TYPE_NAME}"
export DOWNLOADABLE_SOURCES
DOWNLOADABLE_SOURCES="true"
