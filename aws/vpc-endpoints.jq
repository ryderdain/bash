.VpcEndpoints[]
| select(
      .VpcEndpointType=="Interface" or .VpcEndpointType=="Gateway"
  )
|[ 
  ( .Tags[]
    | select(.Key=="Name")
    | .Value
  ),
  .ServiceName,
  .VpcEndpointId,
  ( .DnsEntries[] | .DnsName)
]
