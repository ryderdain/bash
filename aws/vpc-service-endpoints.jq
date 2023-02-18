[.VpcEndpoints[]
| select(
      .VpcEndpointType=="Interface"
    and (
      .ServiceName | contains("vpce") | not
    )
  )
|{
  "Name": ( .Tags[]
    | select(.Key=="Name")
    | .Value
  ),
  "Service": (.ServiceName),
  "State": (.State),
  "VpceId": (.VpcEndpointId),
  "Subnets": (.SubnetIds),
  "DnsNames": ([ .DnsEntries[]
      | .DnsName
    ])
  }
]
