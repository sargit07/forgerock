# Source these values for a mini cluster - useful for small tests

# Change cluster name to a unique name that can include alphanumeric characters and hyphens only.
export NAME="mini"

# cluster-up.sh retrieves the region from the user's gcloud config.
# NODE_LOCATIONS refers to the zones to be used by CDM in the region. If your region doesn't include zones a,b or c then uncomment and set the REGION, ZONE and NODE_LOCATIONS appropriately to override:
# export REGION=us-east1
# export NODE_LOCATIONS="$REGION-b,$REGION-c,$REGION-d"
# export ZONE="$REGION-b" # required for cluster master

# The machine types for primary and ds node pools
export MACHINE=e2-standard-2
export DS_MACHINE=e2-standard-2
export CREATE_DS_POOL=false

# Values for creating a static IP
export CREATE_STATIC_IP=false # set to true to create a static IP.
# export STATIC_IP_NAME="" # uncomment to provide a unique name(defaults to cluster name).  Lowercase letters, numbers, hyphens allowed.
export DELETE_STATIC_IP=false # set to true to delete static IP, named above, when running cluster-down.sh