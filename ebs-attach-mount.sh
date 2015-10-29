#!/bin/bash

# Parse input arguments
while [[ $# > 1 ]]
do
key="$1"

# Parse arguments
case $key in
  -c|--command)
  COMMAND="$2"
  shift # past argument
  ;;
  -v|--volume-name)
  VOLUME_NAME="$2"
  shift # past argument
  ;;
  -m|--mount-point)
  MOUNT="$2"
  shift # past argument
  ;;
  *)
    # unknown option
  ;;
esac
shift
done

# Detect free block device
function detect_free_block_device {
  for x in {a..z}
  do
    DEVICE="/dev/xvd$x"
    if [ ! -b $DEVICE ]
    then
      break
    fi
  done
}

source /ecs/ecs.config
VOLUME_NAME=$ECS_CLUSTER-$CONTAINER
# Find volume by Name
function find_volume_by_name {
  # Extract region
  REGION=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
  VOLUME=$(aws ec2 describe-volumes --region $REGION --filters Name=tag-key,Values=Name Name=tag-value,Values=$VOLUME_NAME Name=status,Values='available' --query 'Volumes[0].VolumeId' --output text)
  if [ -z $VOLUME ]
  then
    echo "Didn't find detached volume with name '$VOLUME_NAME'"
    exit 1
  fi
}

# Attach and mount volume
function attach_and_mount_volume {
  # Get instance id
  INSTANCE=$(curl http://169.254.169.254/latest/meta-data/instance-id)
  echo Instance ID is $INSTANCE
  
  if ! aws ec2 attach-volume --volume-id $VOLUME --instance-id $INSTANCE --device $DEVICE --region $REGION
  then
    exit 1
  fi
  echo Attaching volume as $DEVICE

  # TODO: FIX WHEN DOCKER CAN DETECT NEW DEVICE
  # Waiting for volume to be attached
  # while [ ! -b $DEVICE ]
  # do
  #   sleep 2
  # done
  
  sleep 5 # Waiting just in case
  mknod $DEVICE b 202 16 # Block device with magic numbers

  # Create directory
  mkdir -p $MOUNT
  # Mount volume
  mount $DEVICE $MOUNT
  echo Mounted volume as $MOUNT
}

# Detach volume
function detach {
  # Detach volume
  echo Unmounting and detaching volume
  umount $MOUNT
  aws ec2 detach-volume --volume-id $VOLUME --region $REGION
}

# Run steps
detect_free_block_device
find_volume_by_name
attach_and_mount_volume
trap detach EXIT

/docker-entrypoint.sh postgres
