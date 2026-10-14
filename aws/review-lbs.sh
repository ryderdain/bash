#!/usr/bin/env bash

# Runs with no arguments. Set AWS_PROFILE to target your environment.
# Output is machine-ready. Pipe through jq -s to read.

application_load_balancers=($(
    aws elbv2 describe-load-balancers \
    | jq -r '.LoadBalancers[]|select(.Type=="application")|.LoadBalancerArn'
  )
)
network_load_balancers=($(
    aws elbv2 describe-load-balancers \
    | jq -r '.LoadBalancers[]|select(.Type=="network")|.LoadBalancerArn'
  )
)

printf '{"LoadBalancers":['
load_balancer_count=0
for load_balancer in ${network_load_balancers[@]} ${application_load_balancers[@]} 
do
  [[ $load_balancer_count -gt 0 ]] && printf ', '
  printf '{"LoadBalancerArn":"%s", "TargetGroups":[' "$load_balancer"

  unset target_groups
  # We can't check LBs that aren't forwarding somewhere
  target_groups=($(
    aws elbv2 describe-listeners --load-balancer-arn "$load_balancer" \
    | jq -r '.Listeners[] | select(.DefaultActions[].Type=="forward") |
               .DefaultActions[] | select(.Type=="forward") | 
                 .TargetGroupArn'
  ))
  if [[ ${#target_groups[0]} -eq 0 ]]
  then # No TGs. Move to next load balancer.
    printf ']}'
    ((load_balancer_count++))
    continue

  else # set up maps to list
    target_group_count=0
    for target_group in ${target_groups[@]} 
    do
      [[ $target_group_count -gt 0 ]] && printf ', '
      printf '{"TargetGroupArn": "%s", "Instances": [' "$target_group"

      unset group_instances
      # Use join() to prevent bash from including json elements.
      group_instances=($(
        aws elbv2 describe-target-health --target-group-arn "$target_group" \
        | jq -r '.TargetHealthDescriptions[] | [
                    .Target.Id,
                    .TargetHealth.State
                 ] | join(":")'
      ))
      if [[ ${#group_instances[@]} -eq 0 ]]
      then # no instances. Move to next target group. 
        printf ']}'
        ((target_group_count++))
        continue

      else # set up maps to list
        group_instance_count=0
        for group_instance in ${group_instances[@]}
        do
          [[ $group_instance_count -gt 0 ]] && printf ', '
          printf '{"InstanceId":"%s", "State":"%s"}' "${group_instance%:*}" "${group_instance#*:}"  
          ((group_instance_count++))
        done
        printf ']'
      fi
      printf '}'
      ((target_group_count++))
    done

    printf ']'
  fi
  printf '}'
  ((load_balancer_count++))
done 
printf ']}'
