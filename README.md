# AWS DC/OS CloudWatch Data Reporter

AWS CloudWatch data reporter based on AWS CLI and DC/OS metrics data.

Simple implementation based on a docker container instance running anywhere on your DC/OS cluster. Data is gathered via simple curl API calls to the DC/OS metrics service. Data is pushed to CloudWatch via AWS CLI calls.
The supplied script queries the metrics APIs and reports data once per minute (normal resolution metric). Feel free to modify the data being sent, along with any additional dimensions you might want to track.

In order for this to work, you will have to create the following secrets and attach them to your docker instance:

```bash
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION
```
Also, for authentication against the DC/OS APIs, please supply username and password (service account coming very soon):
```bash
SU_USR
SU_PWD
```
You can build and use your image based on the supplied `Dockerfile` or re-use the one that comes with this repository: `dobriak/aws-rep:0.0.1`.

Here is how you can make use of the reported data to trigger events for your autoscaling groups:

```bash
  policyARN=$(aws autoscaling put-scaling-policy \
    --auto-scaling-group-name <Your ASG name here> \
    --policy-name <Your policy name> \
    --policy-type SimpleScaling \
    --adjustment-type ChangeInCapacity \
    --scaling-adjustment 1 \
    --cooldown 300 | jq -r .PolicyARN)

  aws cloudwatch put-metric-alarm \
    --alarm-name <Your alarm name> \
    --alarm-description "Scale on LoadAverage1m over 5 for more than 2 periods." \
    --metric-name LoadAverage1m \
    --namespace Dcos \
    --statistic Average \
    --period 120 \
    --threshold 5 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --dimensions "Name=AutoScalingGroupName,Value=<Your ASG name here>" \
    --evaluation-periods 2 \
    --alarm-actions ${policyARN}
```

The script currently reports the following custom metrics, all in the Dcos namespace:
```bash
# From the metrics API:
LoadAverage1m
LoadAverage5m
LoadAverage15m
# From the Mesos agents API:
PercentUsedMem
```

