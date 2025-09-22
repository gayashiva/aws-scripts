import json
import boto3
from boto3.dynamodb.conditions import Key, Attr
from datetime import datetime, timedelta, timezone
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Dict, List, Optional, Tuple, Any
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
ses = boto3.client('ses')

# Constants
SENDER_EMAIL = "aws@acresofice.com"
IST_OFFSET = timedelta(hours=5, minutes=30)

# Site configurations - centralized and expandable
SITE_CONFIG = {
    'Sakti': {'name': 'Sakti', 'type': 'air', 'active': True},
    'Stakmo': {'name': 'Stakmo', 'type': 'air', 'active': True},
    'Skuast': {'name': 'Skuast', 'type': 'drip', 'active': True},
    # 'Surya': {'name': 'Surya AIR', 'type': 'air', 'active': True},
    # 'Ayee': {'name': 'Ayee', 'type': 'air', 'active': True},
    # Commented out inactive sites
    # 'Li': {'name': 'Likir', 'type': 'air', 'active': False},
    # 'Ig': {'name': 'Igoo', 'type': 'air', 'active': False},
    # 'Shey': {'name': 'Shey', 'type': 'air', 'active': False},
    # 'Te': {'name': 'Test', 'type': 'drip', 'active': False}
}

# Table mappings
TABLE_CONFIG = {
    'air': 'AIRTable',
    'drip': 'DripTable',
    'errors': 'AIRErrors'
}

class MonitoringSystem:
    def __init__(self):
        self.air_table = dynamodb.Table(TABLE_CONFIG['air'])
        self.drip_table = dynamodb.Table(TABLE_CONFIG['drip'])
        self.error_table = dynamodb.Table(TABLE_CONFIG['errors'])
    
    def get_active_sites(self) -> Dict[str, Dict]:
        """Get all active sites from configuration"""
        return {code: config for code, config in SITE_CONFIG.items() if config['active']}
    
    def get_table_for_site(self, site_code: str):
        """Get the appropriate table based on site type"""
        site_config = SITE_CONFIG.get(site_code, {})
        site_type = site_config.get('type', 'air')
        return self.air_table if site_type == 'air' else self.drip_table
    
    def utc_to_ist(self, utc_time: datetime) -> datetime:
        """Convert UTC time to IST"""
        if utc_time.tzinfo is None:
            utc_time = utc_time.replace(tzinfo=timezone.utc)
        return utc_time + IST_OFFSET
    
    def ist_to_utc(self, ist_time: datetime) -> datetime:
        """Convert IST time to UTC"""
        if ist_time.tzinfo is None:
            ist_time = ist_time.replace(tzinfo=timezone.utc)
        return ist_time - IST_OFFSET
    
    def parse_timestamp(self, timestamp_str: str) -> Optional[datetime]:
        """Parse timestamp string to datetime object"""
        if not timestamp_str:
            return None
        
        try:
            formats_to_try = [
                "%Y-%m-%d %H:%M",
                "%Y-%m-%dT%H:%M:%S",
                "%Y-%m-%dT%H:%M:%SZ",
                "%Y-%m-%dT%H:%M:%S.%fZ"
            ]
            
            for fmt in formats_to_try:
                try:
                    if timestamp_str.endswith('Z'):
                        dt = datetime.strptime(timestamp_str, fmt)
                        return dt.replace(tzinfo=timezone.utc)
                    else:
                        # Assume IST timestamp from ESP32
                        dt = datetime.strptime(timestamp_str, fmt)
                        return self.ist_to_utc(dt)
                except ValueError:
                    continue
            
            # If all formats fail, try ISO format
            return datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            
        except Exception as e:
            logger.error(f"Error parsing timestamp {timestamp_str}: {e}")
            return None
    
    def format_timestamp_for_display(self, timestamp_str: str) -> str:
        """Format timestamp for display in IST"""
        parsed_time = self.parse_timestamp(timestamp_str)
        if parsed_time:
            ist_time = self.utc_to_ist(parsed_time)
            return ist_time.strftime("%Y-%m-%d %H:%M IST")
        return "Unknown time"


class DataReporter(MonitoringSystem):
    """Handles data querying and reporting functionality"""
    
    def query_site_data(self, site_code: str, count: int = 5) -> List[Dict]:
        """Query data for a specific site"""
        try:
            table = self.get_table_for_site(site_code)
            response = table.query(
                KeyConditionExpression=Key('site_name').eq(site_code),
                Limit=count,
                ScanIndexForward=False
            )
            return response.get('Items', [])
        except Exception as e:
            logger.error(f"Error querying site {site_code}: {e}")
            return []
    
    def format_site_data_text(self, site_code: str, items: List[Dict]) -> str:
        """Format site data as plain text"""
        site_config = SITE_CONFIG.get(site_code, {})
        site_name = site_config.get('name', site_code)
        site_type = site_config.get('type', 'air')
        
        output = [f"=== Site: {site_name} ({site_code}) [{site_type}] ==="]
        
        if site_type == 'drip':
            output.append("TIMESTAMP\tSOIL_1\tSOIL_2\tTEMP\tDISCHARGE\tPRESSURE\tCOUNTER")
            for item in items:
                row = "\t".join([
                    item.get('timestamp', 'N/A'),
                    str(item.get('soil_1', 'N/A')),
                    str(item.get('soil_2', 'N/A')),
                    str(item.get('temperature', 'N/A')),
                    str(item.get('discharge', 'N/A')),
                    str(item.get('pressure', 'N/A')),
                    str(item.get('counter', 'N/A'))
                ])
                output.append(row)
        else:  # air
            output.append("TIMESTAMP\tTEMP\tWATER_TEMP\tDISCHARGE\tPRESSURE\tCOUNTER")
            for item in items:
                row = "\t".join([
                    item.get('timestamp', 'N/A'),
                    str(item.get('temperature', 'N/A')),
                    str(item.get('water_temp', 'N/A')),
                    str(item.get('discharge', 'N/A')),
                    str(item.get('pressure', 'N/A')),
                    str(item.get('counter', 'N/A'))
                ])
                output.append(row)
        
        return "\n".join(output) + "\n\n"
    
    def format_site_data_html(self, site_code: str, items: List[Dict]) -> str:
        """Format site data as HTML table"""
        site_config = SITE_CONFIG.get(site_code, {})
        site_name = site_config.get('name', site_code)
        site_type = site_config.get('type', 'air')
        
        html = f"""
        <h2>Site: {site_name} ({site_code}) [{site_type}]</h2>
        <table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; margin-bottom: 20px;">
        """
        
        if site_type == 'drip':
            html += """
            <tr style="background-color: #f2f2f2;">
                <th>Timestamp</th><th>Soil A</th><th>Soil B</th><th>Temperature</th>
                <th>Discharge</th><th>Pressure</th><th>Counter</th>
            </tr>
            """
            for item in items:
                html += f"""
                <tr>
                    <td>{item.get('timestamp', 'N/A')}</td>
                    <td>{item.get('soil_1', 'N/A')}</td>
                    <td>{item.get('soil_2', 'N/A')}</td>
                    <td>{item.get('temperature', 'N/A')}</td>
                    <td>{item.get('discharge', 'N/A')}</td>
                    <td>{item.get('pressure', 'N/A')}</td>
                    <td>{item.get('counter', 'N/A')}</td>
                </tr>
                """
        else:  # air
            html += """
            <tr style="background-color: #f2f2f2;">
                <th>Timestamp</th><th>Temperature</th><th>Water Temp</th><th>Discharge</th>
                <th>Pressure</th><th>Counter</th>
            </tr>
            """
            for item in items:
                html += f"""
                <tr>
                    <td>{item.get('timestamp', 'N/A')}</td>
                    <td>{item.get('temperature', 'N/A')}</td>
                    <td>{item.get('water_temp', 'N/A')}</td>
                    <td>{item.get('discharge', 'N/A')}</td>
                    <td>{item.get('pressure', 'N/A')}</td>
                    <td>{item.get('counter', 'N/A')}</td>
                </tr>
                """
        
        html += "</table>"
        return html


class OfflineMonitor(MonitoringSystem):
    """Handles offline site monitoring functionality"""
    
    def get_latest_timestamp(self, site_code: str) -> Optional[str]:
        """Get the most recent timestamp for a site"""
        try:
            table = self.get_table_for_site(site_code)
            logger.info(f"Querying table {table.table_name} for site {site_code}")

            response = table.query(
                KeyConditionExpression=Key('site_name').eq(site_code),
                Limit=1,
                ScanIndexForward=False
            )

            items = response.get('Items', [])
            if items:
                timestamp = items[0].get('timestamp')
                logger.info(f"Found latest timestamp for {site_code}: {timestamp}")
                return timestamp
            else:
                logger.warning(f"No items found for site {site_code} in table {table.table_name}")
                return None

        except Exception as e:
            logger.error(f"Error querying site {site_code}: {e}")
            return None
    
    def check_site_status(self, timestamp_str: str, max_hours: int = 2) -> Tuple[bool, Optional[float]]:
        """Check if site has reported data within the specified time window"""
        parsed_time = self.parse_timestamp(timestamp_str)
        if not parsed_time:
            return False, None
        
        try:
            current_time = datetime.now(timezone.utc)
            hours_since_last_report = (current_time - parsed_time).total_seconds() / 3600
            is_active = hours_since_last_report <= max_hours
            
            logger.info(f"Site last reported: {timestamp_str}, Hours ago: {hours_since_last_report:.2f}, Active: {is_active}")
            return is_active, hours_since_last_report
            
        except Exception as e:
            logger.error(f"Error checking timestamp {timestamp_str}: {e}")
            return False, None
    
    def get_offline_sites(self, max_hours: int = 2) -> Dict[str, Dict]:
        """Get all sites that haven't reported in the specified time window"""
        offline_sites = {}

        for site_code in self.get_active_sites():
            try:
                logger.info(f"Checking site: {site_code}")
                latest_timestamp = self.get_latest_timestamp(site_code)

                if latest_timestamp is None:
                    logger.warning(f"No data found for site {site_code} - marking as offline")
                    offline_sites[site_code] = {
                        'last_timestamp': None,
                        'hours_offline': None
                    }
                else:
                    is_active, hours_offline = self.check_site_status(latest_timestamp, max_hours)

                    if not is_active:
                        offline_sites[site_code] = {
                            'last_timestamp': latest_timestamp,
                            'hours_offline': hours_offline
                        }
            except Exception as e:
                logger.error(f"Error processing site {site_code}: {e}")
                offline_sites[site_code] = {
                    'last_timestamp': None,
                    'hours_offline': None
                }

        return offline_sites


class ErrorMonitor(MonitoringSystem):
    """Handles error monitoring functionality"""
    
    def get_recent_errors_for_site(self, site_code: str, hours: int = 24, limit: int = 5) -> List[Dict]:
        """Get recent errors for a specific site"""
        try:
            current_time = datetime.now(timezone.utc)
            cutoff_time = current_time - timedelta(hours=hours)
            cutoff_timestamp = cutoff_time.isoformat()
            
            logger.info(f"Querying errors for site {site_code} since {cutoff_timestamp}")
            
            response = self.error_table.scan(
                FilterExpression=Attr('site_name').eq(site_code) & 
                               Attr('timestamp').gte(cutoff_timestamp),
                Limit=50
            )
            
            errors = response.get('Items', [])
            logger.info(f"Found {len(errors)} errors for site {site_code}")
            
            # Sort by timestamp and limit results
            errors.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
            return errors[:limit]
            
        except Exception as e:
            logger.error(f"Error querying errors for site {site_code}: {e}")
            return []
    
    def get_all_sites_recent_errors(self, hours: int = 24, limit: int = 5) -> Dict[str, List[Dict]]:
        """Get recent errors for all active sites"""
        all_errors = {}
        
        for site_code in self.get_active_sites():
            errors = self.get_recent_errors_for_site(site_code, hours, limit)
            if errors:
                all_errors[site_code] = errors
        
        return all_errors


class EmailService:
    """Handles email formatting and sending"""
    
    @staticmethod
    def send_email(text_content: str, html_content: str, recipient_emails: List[str], subject: str) -> Dict:
        """Send email using AWS SES"""
        if isinstance(recipient_emails, str):
            recipient_emails = [recipient_emails]
        
        try:
            response = ses.send_email(
                Source=SENDER_EMAIL,
                Destination={'ToAddresses': recipient_emails},
                Message={
                    'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                    'Body': {
                        'Text': {'Data': text_content, 'Charset': 'UTF-8'},
                        'Html': {'Data': html_content, 'Charset': 'UTF-8'}
                    }
                }
            )
            logger.info(f"Email sent successfully to {recipient_emails}")
            return response
        except Exception as e:
            logger.error(f"Error sending email: {e}")
            raise
    
    @staticmethod
    def format_offline_alert_email(offline_sites: Dict[str, Dict]) -> Tuple[str, str]:
        """Format offline sites alert email"""
        if not offline_sites:
            return None, None
        
        # Text content
        text_content = "⚠️ URGENT ALERT: The following sites have not reported data in the last 2 hours:\n\n"
        for site_code, data in offline_sites.items():
            site_config = SITE_CONFIG.get(site_code, {})
            site_name = site_config.get('name', site_code)
            last_timestamp = data.get('last_timestamp')
            hours_offline = data.get('hours_offline')
            
            text_content += f"Site: {site_name} ({site_code})\n"
            text_content += f"Last report: {last_timestamp if last_timestamp else 'No data available'} (IST)\n"
            if hours_offline:
                text_content += f"Hours since last report: {hours_offline:.1f}\n\n"
            else:
                text_content += "No recent data available\n\n"
        
        # HTML content
        html_content = """
        <html><body>
        <h2 style="color: #FF0000;">⚠️ URGENT ALERT: Sites Offline</h2>
        <p>The following sites have not reported data in the last 2 hours:</p>
        <table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse;">
            <tr style="background-color: #f2f2f2;">
                <th>Site</th><th>Last Report</th><th>Hours Offline</th>
            </tr>
        """
        
        for site_code, data in offline_sites.items():
            site_config = SITE_CONFIG.get(site_code, {})
            site_name = site_config.get('name', site_code)
            last_timestamp = data.get('last_timestamp')
            hours_offline = data.get('hours_offline')
            
            html_content += f"""
            <tr>
                <td><strong>{site_name} ({site_code})</strong></td>
                <td>{last_timestamp if last_timestamp else 'No data available'} (IST)</td>
                <td>{f"{hours_offline:.1f}" if hours_offline else "N/A"}</td>
            </tr>
            """
        
        html_content += """
        </table>
        <p>Please check the site status and ensure data collection systems are functioning properly.</p>
        </body></html>
        """
        
        return text_content, html_content
    
    @staticmethod
    def format_error_summary_email(site_errors: Dict[str, List[Dict]]) -> Tuple[str, str]:
        """Format error summary email"""
        if not site_errors:
            return None, None
        
        monitoring_system = MonitoringSystem()
        total_errors = sum(len(errors) for errors in site_errors.values())
        
        # Text content
        text_content = "🚨 DAILY ERROR SUMMARY (Last 24 Hours)\n\n"
        text_content += f"Total errors across all sites: {total_errors}\n\n"
        
        for site_code, errors in site_errors.items():
            if errors:
                site_config = SITE_CONFIG.get(site_code, {})
                site_name = site_config.get('name', site_code)
                text_content += f"Site: {site_name} ({site_code}) - {len(errors)} error(s):\n"
                text_content += "-" * 50 + "\n"
                
                for i, error in enumerate(errors, 1):
                    error_time = monitoring_system.format_timestamp_for_display(error.get('timestamp', ''))
                    error_msg = error.get('message', 'No message')
                    error_version = error.get('version', 'unknown')
                    text_content += f"{i}. [{error_time}] [v{error_version}] {error_msg}\n"
                
                text_content += "\n"
        
        current_time = datetime.now(timezone.utc) + IST_OFFSET
        text_content += f"Report generated at: {current_time.strftime('%Y-%m-%d %H:%M IST')}"
        
        # HTML content
        html_content = f"""
        <html><body>
        <h2 style="color: #FF6600;">🚨 Daily Error Summary Report</h2>
        <p><strong>Total Errors:</strong> {total_errors} across all sites</p>
        """
        
        if total_errors > 0:
            for site_code, errors in site_errors.items():
                if errors:
                    site_config = SITE_CONFIG.get(site_code, {})
                    site_name = site_config.get('name', site_code)
                    html_content += f"""
                    <h4 style="color: #CC0000;">{site_name} ({site_code}) - {len(errors)} Error(s)</h4>
                    <table border="1" cellpadding="8" cellspacing="0" style="border-collapse: collapse; margin-bottom: 20px; width: 100%;">
                        <tr style="background-color: #f2f2f2;">
                            <th>#</th><th>Time</th><th>Version</th><th>Error Message</th>
                        </tr>
                    """
                    
                    for i, error in enumerate(errors, 1):
                        error_time = monitoring_system.format_timestamp_for_display(error.get('timestamp', ''))
                        error_msg = error.get('message', 'No message')
                        error_version = error.get('version', 'unknown')
                        
                        html_content += f"""
                        <tr>
                            <td><strong>{i}</strong></td>
                            <td>{error_time}</td>
                            <td>v{error_version}</td>
                            <td>{error_msg}</td>
                        </tr>
                        """
                    
                    html_content += "</table>"
        
        current_time = datetime.now(timezone.utc) + IST_OFFSET
        html_content += f"""
        <p><em>Report generated at: {current_time.strftime('%Y-%m-%d %H:%M IST')}</em></p>
        </body></html>
        """
        
        return text_content, html_content


def lambda_handler(event, context):
    """
    Unified Lambda handler for all monitoring operations
    
    Event format:
    {
        "operation": "data_report"|"offline_check"|"error_summary",
        "email": ["recipient@example.com"] or "recipient@example.com",
        
        // For data_report operation:
        "queryType": "single"|"all",
        "siteName": "Sakti"|"Stakmo"|etc,  // Only for single site
        "count": 5,  // Optional, defaults to 5
        "subject": "Custom subject",  // Optional
        
        // For offline_check operation:
        "max_hours": 2,  // Optional, defaults to 2
        
        // For error_summary operation:
        "hours": 24,  // Optional, defaults to 24
        "limit": 5   // Optional, defaults to 5 errors per site
    }
    """
    try:
        operation = event.get('operation')
        if not operation:
            raise ValueError("Operation is required. Must be one of: data_report, offline_check, error_summary")
        
        # Get current IST time for logging
        current_time = datetime.now(timezone.utc) + IST_OFFSET
        logger.info(f"Operation: {operation}, Current time (IST): {current_time.strftime('%Y-%m-%d %H:%M')}")
        
        # Validate email recipients
        recipient_emails = event.get('email')
        if not recipient_emails:
            raise ValueError("Email recipient(s) are required")
        
        if isinstance(recipient_emails, str):
            recipient_emails = [recipient_emails]
        
        if not isinstance(recipient_emails, list):
            raise ValueError("Email must be a string or list of strings")
        
        # Route to appropriate operation
        if operation == "data_report":
            return handle_data_report(event, recipient_emails)
        elif operation == "offline_check":
            return handle_offline_check(event, recipient_emails)
        elif operation == "error_summary":
            return handle_error_summary(event, recipient_emails)
        else:
            raise ValueError(f"Invalid operation: {operation}")
    
    except Exception as e:
        logger.error(f"Error in lambda_handler: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def handle_data_report(event: Dict, recipient_emails: List[str]) -> Dict:
    """Handle data reporting operation"""
    reporter = DataReporter()
    query_type = event.get('queryType', 'single')
    count = int(event.get('count', 5))
    custom_subject = event.get('subject')
    
    text_output = ""
    html_output = "<html><body>"
    
    if query_type == 'all':
        # Query all active sites
        for site_code in reporter.get_active_sites():
            try:
                items = reporter.query_site_data(site_code, count)
                text_output += reporter.format_site_data_text(site_code, items)
                html_output += reporter.format_site_data_html(site_code, items)
            except Exception as e:
                error_msg = f"Error querying site {site_code}: {str(e)}\n\n"
                text_output += error_msg
                html_output += f"<p style='color: red;'>{error_msg}</p>"
    else:
        # Query single site
        site_name = event.get('siteName')
        if not site_name:
            raise ValueError("siteName is required for single site query")
        if site_name not in SITE_CONFIG:
            active_sites = list(reporter.get_active_sites().keys())
            raise ValueError(f"Invalid site name. Must be one of: {', '.join(active_sites)}")
        
        items = reporter.query_site_data(site_name, count)
        text_output += reporter.format_site_data_text(site_name, items)
        html_output += reporter.format_site_data_html(site_name, items)
    
    html_output += "</body></html>"
    
    # Send email
    subject = custom_subject or "Site Data Report"
    EmailService.send_email(text_output, html_output, recipient_emails, subject)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Data report sent successfully',
            'operation': 'data_report',
            'recipients': recipient_emails
        })
    }


def handle_offline_check(event: Dict, recipient_emails: List[str]) -> Dict:
    """Handle offline site monitoring operation"""
    monitor = OfflineMonitor()
    max_hours = int(event.get('max_hours', 2))
    
    offline_sites = monitor.get_offline_sites(max_hours)
    
    if offline_sites:
        text_content, html_content = EmailService.format_offline_alert_email(offline_sites)
        subject = f"⚠️ URGENT ALERT: Sites Offline - {max_hours}H Check"
        EmailService.send_email(text_content, html_content, recipient_emails, subject)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Offline alert sent - {len(offline_sites)} sites offline',
                'operation': 'offline_check',
                'offline_sites': {k: v['last_timestamp'] for k, v in offline_sites.items()},
                'recipients': recipient_emails
            })
        }
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'All sites active within {max_hours} hours',
            'operation': 'offline_check',
            'offline_sites': {}
        })
    }


def handle_error_summary(event: Dict, recipient_emails: List[str]) -> Dict:
    """Handle error summary operation"""
    monitor = ErrorMonitor()
    hours = int(event.get('hours', 24))
    limit = int(event.get('limit', 5))
    
    site_errors = monitor.get_all_sites_recent_errors(hours, limit)
    total_errors = sum(len(errors) for errors in site_errors.values())
    
    if site_errors and total_errors > 0:
        text_content, html_content = EmailService.format_error_summary_email(site_errors)
        subject = f"🚨 Error Summary - {total_errors} Total Errors"
        EmailService.send_email(text_content, html_content, recipient_emails, subject)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Error summary sent - {total_errors} total errors',
                'operation': 'error_summary',
                'site_error_counts': {site: len(errors) for site, errors in site_errors.items()},
                'recipients': recipient_emails
            })
        }
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'No errors found in last {hours} hours',
            'operation': 'error_summary',
            'total_errors': 0
        })
    }
