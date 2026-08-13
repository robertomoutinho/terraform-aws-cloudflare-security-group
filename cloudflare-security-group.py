import os
import boto3
import ipaddress
import urllib3
import json
import ast
from botocore.exceptions import ClientError
from datetime import datetime

# Sentinel the caller puts in policy_template wherever the CIDR list belongs.
# Replaced with a JSON array of Cloudflare's current ranges.
IP_RANGE_SENTINEL = "__CLOUDFLARE_IP_RANGES__"

def get_cloudflare_ip_list():
    """Call the CloudFlare API and return a list of IPs"""
    http = urllib3.PoolManager()
    response = http.request("GET","https://api.cloudflare.com/client/v4/ips")
    temp = json.loads(response.data.decode("utf-8"))
    ip_addresses_list = []
    if 'result' in temp:
        if 'ipv4_cidrs' in temp['result']:
            for ip in temp['result']['ipv4_cidrs']:
                ip_addresses_list.append(ip)
        if 'ipv6_cidrs' in temp['result']:
            for ip in temp['result']['ipv6_cidrs']:
                ip_addresses_list.append(ip)
    return ip_addresses_list

def get_aws_security_group(group_id):
    """Return the defined Security Group"""
    ec2 = boto3.resource('ec2')
    group = ec2.SecurityGroup(group_id)
    if group.group_id == group_id:
        return group
    raise Exception('Failed to retrieve Security Group')

def check_rule_exists(rules, address, port):
    """Check if the rule currently exists"""
    rule_exists = False
    for rule in rules:
        for ip_range in rule['IpRanges']:
            if ip_range['CidrIp'] == address and rule['FromPort'] == port:
                rule_exists = True
        for ip_range in rule['Ipv6Ranges']:
            if ip_range['CidrIpv6'] == address and rule['FromPort'] == port:
                rule_exists = True
    return rule_exists

def get_existing_ip_addresses(rules):
    ip_addresses = []
    for rule in rules:
        for ip_range in rule['IpRanges']:
            ip_addresses.append(ip_range['CidrIp'])
        for ip_range in rule['Ipv6Ranges']:
            ip_addresses.append(ip_range['CidrIpv6'])
    return set(ip_addresses)

def add_rule(group, address, port):
    """Add the ip address/port to the security group"""
    ip = ipaddress.ip_network(address)
    if isinstance(ip, ipaddress.IPv4Network):
        group.authorize_ingress(IpProtocol="tcp", CidrIp=address, FromPort=port, ToPort=port)
    elif isinstance(ip, ipaddress.IPv6Network):
        permission = [
            {  
            'IpProtocol': 'TCP',
            'FromPort': port,
            'ToPort': port,
            'Ipv6Ranges': [{'CidrIpv6': address}]
            }
        ]
        group.authorize_ingress(IpPermissions=permission)

    print("Added %s : %i  " % (address, port))

def remove_rule(group, address, port):
    """Remove the ip address/port from the security group"""
    ip = ipaddress.ip_network(address)
    if isinstance(ip, ipaddress.IPv4Network):
        group.revoke_ingress(IpProtocol="tcp", CidrIp=address, FromPort=port, ToPort=port)
    elif isinstance(ip, ipaddress.IPv6Network):
        permission = [
            {  
            'IpProtocol': 'TCP',
            'FromPort': port,
            'ToPort': port,
            'Ipv6Ranges': [{'CidrIpv6': address}]
            }
        ]
        group.revoke_ingress(IpPermissions=permission)
    
    print("Removed %s : %i  " % (address, port))


def get_s3_bucket_policy_targets():
    """Return the configured S3 bucket policy targets, or [] if unconfigured.

    Absent and empty are both normal: the feature is opt-in and every consumer
    that predates it leaves the variable at its default.
    """
    raw = os.environ.get('S3_BUCKET_POLICY_TARGETS', '').strip()
    if not raw:
        return []
    return json.loads(raw)


def render_ip_ranges(node, ip_addresses):
    """Recursively replace the sentinel string with the CIDR list.

    Walks the parsed policy rather than doing text substitution on the raw
    JSON, so the CIDR list cannot break the document's quoting or escaping and
    the sentinel can sit at any depth.
    """
    if isinstance(node, dict):
        return {k: render_ip_ranges(v, ip_addresses) for k, v in node.items()}
    if isinstance(node, list):
        return [render_ip_ranges(v, ip_addresses) for v in node]
    if node == IP_RANGE_SENTINEL:
        return list(ip_addresses)
    return node


def update_s3_bucket_policies(targets, ip_addresses):
    """Render each target's policy template and PUT it if it changed."""
    if not targets:
        return

    if not ip_addresses:
        # Never write an empty allowlist. An upstream hiccup that returned no
        # ranges would otherwise lock Cloudflare out of every bucket at once.
        raise Exception('Refusing to update bucket policies with an empty IP list')

    s3 = boto3.client('s3')

    for target in targets:
        bucket = target['bucket']
        template = json.loads(target['policy_template'])
        desired = render_ip_ranges(template, ip_addresses)

        if IP_RANGE_SENTINEL in json.dumps(desired):
            raise Exception(
                'Sentinel %s still present after rendering policy for %s'
                % (IP_RANGE_SENTINEL, bucket)
            )

        try:
            current = json.loads(
                s3.get_bucket_policy(Bucket=bucket)['Policy']
            )
        except ClientError as error:
            # NoSuchBucketPolicy is not a modelled S3 exception, so it cannot be
            # caught as s3.exceptions.NoSuchBucketPolicy -- check the code.
            if error.response['Error']['Code'] != 'NoSuchBucketPolicy':
                raise
            # First run after the bucket was created. Expected, not an error.
            current = None

        if current == desired:
            print("Bucket policy already current: %s" % bucket)
            continue

        s3.put_bucket_policy(Bucket=bucket, Policy=json.dumps(desired))
        print("Updated bucket policy: %s (%i ranges)" % (bucket, len(ip_addresses)))


def lambda_handler(event, context):
    """aws lambda main func"""
    ports = [int(x) for x in os.environ.get('PORTS_LIST', '').split(",") if x]
    if not ports:
        ports = ast.literal_eval(os.environ['ALLOWED_PORTS'])

    security_group = get_aws_security_group(os.environ['SECURITY_GROUP_ID'])
    current_rules = security_group.ip_permissions
    ip_addresses = get_cloudflare_ip_list()

    ## Add IPs
    for ip_address in ip_addresses:
        for port in ports:
            if not check_rule_exists(current_rules, ip_address, port):
                add_rule(security_group, ip_address, int(port))

    ## Remove IPs from SG that are not in list
    for ip_address in get_existing_ip_addresses(current_rules):
        if (ip_address not in ip_addresses):
            for port in ports:
                remove_rule(security_group, ip_address, int(port))

    ## Bucket policies last, so a failure here cannot leave the security group
    ## half-updated. Existing consumers configure no targets and skip this.
    update_s3_bucket_policies(get_s3_bucket_policy_targets(), ip_addresses)