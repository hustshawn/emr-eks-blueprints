#!/bin/bash

# read -p "Enter EMR Virtual Cluster AWS Region: " AWS_REGION
# read -p "Enter the EMR Virtual Cluster ID: " EMR_VIRTUAL_CLUSTER_ID
# read -p "Enter the EMR Execution Role ARN: " EMR_EXECUTION_ROLE_ARN
# read -p "Enter the CloudWatch Log Group name: " CLOUDWATCH_LOG_GROUP
# read -p "Enter the S3 Bucket for storing PySpark Scripts, Pod Templates and Input data. For e.g., s3://<bucket-name>: " S3_BUCKET

# cp ../../../terraform.tfstate .
AWS_REGION="us-west-2"
TEMP_DIR=$(mktemp -d)
TF_OUTPUT=$(terraform output -json emr_on_eks > $TEMP_DIR/emr_on_eks.json)
EMR_VIRTUAL_CLUSTER_ID=$(cat $TEMP_DIR/emr_on_eks.json | jq -r '."data-team-a".virtual_cluster_id')
EMR_EXECUTION_ROLE_ARN=$(cat $TEMP_DIR/emr_on_eks.json | jq -r '."data-team-a".job_execution_role_arn')
CLOUDWATCH_LOG_GROUP=$(cat $TEMP_DIR/emr_on_eks.json | jq -r '."data-team-a".cloudwatch_log_group_name')

S3_BUCKET="s3://$(terraform output -raw emr_s3_bucket_name)"
echo "Virtual Cluster ID: $EMR_VIRTUAL_CLUSTER_ID"
echo "Execution Role ARN: $EMR_EXECUTION_ROLE_ARN"
echo "CloudWatch Log Group: $CLOUDWATCH_LOG_GROUP"

#--------------------------------------------
# DEFAULT VARIABLES CAN BE MODIFIED
#--------------------------------------------
JOB_NAME='taxidata'
EMR_EKS_RELEASE_LABEL="emr-6.10.0-latest" # Spark 3.3.1

SPARK_JOB_S3_PATH="${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/${JOB_NAME}"
SCRIPTS_S3_PATH="${SPARK_JOB_S3_PATH}/scripts"
INPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/input"
OUTPUT_DATA_S3_PATH="${SPARK_JOB_S3_PATH}/output"
# echo $SPARK_JOB_S3_PATH, $SCRIPTS_S3_PATH, $INPUT_DATA_S3_PATH, $OUTPUT_DATA_S3_PATH

#--------------------------------------------
# Execute Spark job
#--------------------------------------------
aws emr-containers start-job-run \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --name $JOB_NAME \
  --region $AWS_REGION \
  --execution-role-arn $EMR_EXECUTION_ROLE_ARN \
  --release-label $EMR_EKS_RELEASE_LABEL \
  --job-driver '{
    "sparkSubmitJobDriver": {
      "entryPoint": "'"$SCRIPTS_S3_PATH"'/pyspark-taxi-trip.py",
      "entryPointArguments": ["'"$INPUT_DATA_S3_PATH"'",
        "'"$OUTPUT_DATA_S3_PATH"'"
      ],
      "sparkSubmitParameters": "--conf spark.executor.instances=2"
    }
  }' \
  --configuration-overrides '{
    "applicationConfiguration": [
        {
          "classification": "spark-defaults",
          "properties": {
            "spark.driver.cores":"1",
            "spark.executor.cores":"1",
            "spark.driver.memory": "4g",
            "spark.executor.memory": "4g",
            "spark.kubernetes.driver.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/driver-pod-template.yaml",
            "spark.kubernetes.executor.podTemplateFile":"'"$SCRIPTS_S3_PATH"'/executor-pod-template.yaml",
            "spark.local.dir":"/data1",
            "spark.kubernetes.submission.connectionTimeout": "60000000",
            "spark.kubernetes.submission.requestTimeout": "60000000",
            "spark.kubernetes.driver.connectionTimeout": "60000000",
            "spark.kubernetes.driver.requestTimeout": "60000000",
            "spark.kubernetes.executor.podNamePrefix":"'"$JOB_NAME"'",
            "spark.metrics.appStatusSource.enabled":"true",
            "spark.ui.prometheus.enabled":"true",
            "spark.executor.processTreeMetrics.enabled":"true",
            "spark.kubernetes.driver.annotation.prometheus.io/scrape":"true",
            "spark.kubernetes.driver.annotation.prometheus.io/path":"/metrics/executors/prometheus/",
            "spark.kubernetes.driver.annotation.prometheus.io/port":"4040",
            "spark.kubernetes.driver.service.annotation.prometheus.io/scrape":"true",
            "spark.kubernetes.driver.service.annotation.prometheus.io/path":"/metrics/driver/prometheus/",
            "spark.kubernetes.driver.service.annotation.prometheus.io/port":"4040",
            "spark.metrics.conf.*.sink.prometheusServlet.class":"org.apache.spark.metrics.sink.PrometheusServlet",
            "spark.metrics.conf.*.sink.prometheusServlet.path":"/metrics/driver/prometheus/",
            "spark.metrics.conf.master.sink.prometheusServlet.path":"/metrics/master/prometheus/",
            "spark.metrics.conf.applications.sink.prometheusServlet.path":"/metrics/applications/prometheus/"
          }
        }
      ],
    "monitoringConfiguration": {
      "persistentAppUI":"ENABLED",
      "cloudWatchMonitoringConfiguration": {
        "logGroupName":"'"$CLOUDWATCH_LOG_GROUP"'",
        "logStreamNamePrefix":"'"$JOB_NAME"'"
      },
      "s3MonitoringConfiguration": {
        "logUri":"'"${S3_BUCKET}/logs/"'"
      }
    }
  }'
