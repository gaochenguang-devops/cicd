#!/bin/bash
set -uo pipefail
J='http://192.168.200.12:30088'
AU='breakglass:__JENKINS_BREAKGLASS_PASS__'
curl -s -u "$AU" "$J/job/maven-demo-pipeline/lastBuild/api/json?tree=number,building,result,duration"; echo
curl -s -u "$AU" "$J/job/maven-demo-pipeline/lastBuild/consoleText" | grep -nE 'ERROR|manifest_http|artifact_sha|已推送到|Finished|BUILD SUCCESS|Stage ' | tail -25
