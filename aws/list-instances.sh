#!/bin/sh

# grab an instance list with most useful information
aws ec2 describe-instances --filters "Name=subnet-id,Values=${1:-"subnet-12345678"}" | jq '
.Reservations[] |
    { (.ReservationId): 
      (.Instances[] |
          { (.InstanceId): {
            "Name": (.Tags[]|select(.Key=="Name")|.Value),
            "User": (.Tags[]|select(.Key=="User")|.Value),
            "Service": (.Tags[]|select(.Key=="Service")|.Value),
            "State": (.State.Name),
            "IpAddress": (.PrivateIpAddress)
            }
          }
      )
    }
'
