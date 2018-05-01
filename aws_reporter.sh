#!/bin/bash
# To be run under a service account in DC/OS
set -x
private_agents=""
master="leader.mesos"
function get_token() {
  if [ ! -f token ]; then
    #Get token
    #token=$(curl --silent -H "Accept: application/json" -H "Content-type: application/json" -X POST -d '{"uid":"'${SU_USR}'","password":"'${SU_PWD}'"}' http://${master}/acs/api/v1/auth/login | jq -r ".token")
    #echo ${token} > token
    ./get_token.sh 
  else
    token=$(cat token)
  fi
}

function get_private_agents() {
  curl -f --silent -X GET -H "Authorization: token=${token}" http://${master}/mesos/slaves > slaves.json
  for row in $(cat slaves.json | jq -r '.slaves[] | @base64'); do
    _jq() {
      echo ${row} | base64 -d | jq -r ${1}
    }
    public_node=$(_jq '.attributes.public_ip')
    if [ "${public_node}" != "true" ]; then
      id=$(_jq '.id')
      private_agents="${private_agents} ${id}"
    fi
  done
  private_agents=$(echo ${private_agents} | xargs)
}

function get_metrics() {
  # Agent ID
  for id in ${private_agents}; do
    curl -f --silent -X GET -H "Authorization: token=${token}" http://${master}/system/v1/agent/${id}/metrics/v0/node > metrics-${id}.json
  done
}

function report_metrics() {
  for id in ${private_agents}; do
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    load1m=$(cat metrics-${id}.json | jq '.datapoints[] | select(.name=="load.1min") | .value')
    load5m=$(cat metrics-${id}.json | jq '.datapoints[] | select(.name=="load.5min") | .value')
    load15m=$(cat metrics-${id}.json | jq '.datapoints[] | select(.name=="load.15min") | .value')
    echo "${ts}:${id} load1m:${load1m}  load5m:${load5m} load15m:${load15m}"
    aws cloudwatch put-metric-data --metric-name LoadAverage1m --namespace Dcos --value ${load1m} --dimensions InstanceId=${id} --timestamp ${ts}
    aws cloudwatch put-metric-data --metric-name LoadAverage5m --namespace Dcos --value ${load5m} --dimensions InstanceId=${id} --timestamp ${ts}
    aws cloudwatch put-metric-data --metric-name LoadAverage15m --namespace Dcos --value ${load15m} --dimensions InstanceId=${id} --timestamp ${ts}
  done
}

function report_percent_usage() {
  for id in ${private_agents}; do
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    all_mem=$(cat slaves.json | jq '.slaves[] | select(.id=="'${id}'") | .resources.mem')
    used_mem=$(cat slaves.json | jq '.slaves[] | select(.id=="'${id}'") | .used_resources.mem')
    pct_used_mem=$(( used_mem * 100 / all_mem ))
    echo "${ts}:${id} resources.mem:${all_mem} used_resources.mem:${used_mem} percent_used_mem:${pct_used_mem}%"
    aws cloudwatch put-metric-data --metric-name PercentUsedMem --namespace Dcos --value ${pct_used_mem} --dimensions InstanceId=${id} --timestamp ${ts}
  done
}

# Main
get_token
while true; do
  (
    get_private_agents
    get_metrics
    report_metrics
    report_percent_usage
  )
  status=$?
  if [ ${status} = 22 ]; then
    rm token
    get_token
  else
    exit ${status}
  fi
  sleep 1m
done
