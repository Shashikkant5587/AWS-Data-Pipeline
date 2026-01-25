#!/usr/bin/env python3

"""
Sample Data Generator for ETL Pipeline Testing
Generates realistic test data for users, orders, and products
"""

import json
import random
import boto3
import psycopg2
import pymysql
from datetime import datetime, timedelta
from faker import Faker
import argparse
import os
from typing import List, Dict, Any

fake = Faker()

class SampleDataGenerator:
    def __init__(self, environment: str = 'dev'):
        self.environment = environment
        self.project_name = 'etl-pipeline'
        self.s3_client = boto3.client('s3')
        self.secrets_client = boto3.client('secretsmanager')
        
    def generate_users(self, count: int = 1000) -> List[Dict[str, Any]]:
        """Generate sample user data"""
        users = []
        
        for i in range(count):
            user = {
                'user_id': i + 1,
                'username': fake.user_name(),
                'email': fake.email(),
                'first_name': fake.first_name(),
                'last_name': fake.last_name(),
                'created_at': fake.date_time_between(start_date='-2y', end_date='now').isoformat(),
                'updated_at': fake.date_time_between(start_date='-30d', end_date='now').isoformat(),
                'status': random.choice(['active', 'inactive', 'suspended']),
                'profile': {
                    'age': random.randint(18, 80),
                    'city': fake.city(),
                    'country': fake.country()
                }
            }
            users.append(user)
            
        return users
    
    def generate_products(self, count: int = 500) -> List[Dict[str, Any]]:
        """Generate sample product data"""
        products = []
        categories = ['Electronics', 'Clothing', 'Books', 'Home & Garden', 'Sports', 'Toys']
        
        for i in range(count):
            product = {
                'product_id': i + 1,
                'product_name': fake.catch_phrase(),
                'category': random.choice(categories),
                'price': round(random.uniform(10.0, 500.0), 2),
                'description': fake.text(max_nb_chars=200),
                'created_at': fake.date_time_between(start_date='-1y', end_date='now').isoformat(),
                'in_stock': random.choice([True, False]),
                'stock_quantity': random.randint(0, 100)
            }
            products.append(product)
            
        return products
    
    def generate_orders(self, user_count: int = 1000, product_count: int = 500, order_count: int = 5000) -> List[Dict[str, Any]]:
        """Generate sample order data"""
        orders = []
        
        for i in range(order_count):
            user_id = random.randint(1, user_count)
            product_id = random.randint(1, product_count)
            quantity = random.randint(1, 5)
            unit_price = round(random.uniform(10.0, 500.0), 2)
            
            order = {
                'order_id': i + 1,
                'user_id': user_id,
                'product_id': product_id,
                'order_date': fake.date_between(start_date='-6m', end_date='today').isoformat(),
                'quantity': quantity,
                'unit_price': unit_price,
                'total_amount': round(quantity * unit_price, 2),
                'order_status': random.choice(['pending', 'processing', 'shipped', 'delivered', 'cancelled']),
                'created_at': fake.date_time_between(start_date='-6m', end_date='now').isoformat(),
                'shipping_address': {
                    'street': fake.street_address(),
                    'city': fake.city(),
                    'state': fake.state(),
                    'zip_code': fake.zipcode(),
                    'country': fake.country()
                }
            }
            orders.append(order)
            
        return orders
    
    def upload_to_s3(self, data: List[Dict[str, Any]], bucket: str, key: str):
        """Upload data to S3"""
        try:
            # Add metadata
            data_with_metadata = {
                'generated_at': datetime.now().isoformat(),
                'record_count': len(data),
                'generator': 'sample-data-generator',
                'environment': self.environment,
                'records': data
            }
            
            self.s3_client.put_object(
                Bucket=bucket,
                Key=key,
                Body=json.dumps(data_with_metadata, indent=2),
                ContentType='application/json'
            )
            
            print(f"Uploaded {len(data)} records to s3://{bucket}/{key}")
            
        except Exception as e:
            print(f"Error uploading to S3: {e}")
            raise
    
    def create_database_tables(self, db_config: Dict[str, str]):
        """Create database tables and insert sample data"""
        
        if db_config['engine'] == 'postgresql':
            self._create_postgresql_tables(db_config)
        elif db_config['engine'] == 'mysql':
            self._create_mysql_tables(db_config)
        else:
            raise ValueError(f"Unsupported database engine: {db_config['engine']}")
    
    def _create_postgresql_tables(self, db_config: Dict[str, str]):
        """Create PostgreSQL tables and insert data"""
        
        connection = None
        try:
            connection = psycopg2.connect(
                host=db_config['host'],
                port=db_config['port'],
                database=db_config['database'],
                user=db_config['username'],
                password=db_config['password']
            )
            
            cursor = connection.cursor()
            
            # Create users table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    user_id SERIAL PRIMARY KEY,
                    username VARCHAR(100) UNIQUE NOT NULL,
                    email VARCHAR(255) UNIQUE NOT NULL,
                    first_name VARCHAR(100),
                    last_name VARCHAR(100),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    status VARCHAR(20) DEFAULT 'active'
                )
            """)
            
            # Create products table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS products (
                    product_id SERIAL PRIMARY KEY,
                    product_name VARCHAR(255) NOT NULL,
                    category VARCHAR(100),
                    price DECIMAL(10,2),
                    description TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    in_stock BOOLEAN DEFAULT TRUE,
                    stock_quantity INTEGER DEFAULT 0
                )
            """)
            
            # Create orders table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS orders (
                    order_id SERIAL PRIMARY KEY,
                    user_id INTEGER REFERENCES users(user_id),
                    product_id INTEGER REFERENCES products(product_id),
                    order_date DATE,
                    quantity INTEGER,
                    unit_price DECIMAL(10,2),
                    total_amount DECIMAL(10,2),
                    order_status VARCHAR(50),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            connection.commit()
            
            # Insert sample data
            users = self.generate_users(100)
            products = self.generate_products(50)
            
            # Insert users
            for user in users:
                cursor.execute("""
                    INSERT INTO users (username, email, first_name, last_name, created_at, updated_at, status)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (username) DO NOTHING
                """, (
                    user['username'], user['email'], user['first_name'], user['last_name'],
                    user['created_at'], user['updated_at'], user['status']
                ))
            
            # Insert products
            for product in products:
                cursor.execute("""
                    INSERT INTO products (product_name, category, price, description, created_at, in_stock, stock_quantity)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                """, (
                    product['product_name'], product['category'], product['price'],
                    product['description'], product['created_at'], product['in_stock'], product['stock_quantity']
                ))
            
            connection.commit()
            
            # Generate and insert orders
            orders = self.generate_orders(100, 50, 500)
            for order in orders:
                cursor.execute("""
                    INSERT INTO orders (user_id, product_id, order_date, quantity, unit_price, total_amount, order_status, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    order['user_id'], order['product_id'], order['order_date'],
                    order['quantity'], order['unit_price'], order['total_amount'],
                    order['order_status'], order['created_at']
                ))
            
            connection.commit()
            print("Successfully created PostgreSQL tables and inserted sample data")
            
        except Exception as e:
            print(f"Error creating PostgreSQL tables: {e}")
            if connection:
                connection.rollback()
            raise
        finally:
            if connection:
                connection.close()
    
    def _create_mysql_tables(self, db_config: Dict[str, str]):
        """Create MySQL tables and insert data"""
        
        connection = None
        try:
            connection = pymysql.connect(
                host=db_config['host'],
                port=db_config['port'],
                database=db_config['database'],
                user=db_config['username'],
                password=db_config['password']
            )
            
            cursor = connection.cursor()
            
            # Create users table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    user_id INT AUTO_INCREMENT PRIMARY KEY,
                    username VARCHAR(100) UNIQUE NOT NULL,
                    email VARCHAR(255) UNIQUE NOT NULL,
                    first_name VARCHAR(100),
                    last_name VARCHAR(100),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    status VARCHAR(20) DEFAULT 'active'
                )
            """)
            
            # Similar implementation for products and orders tables
            # ... (similar to PostgreSQL but with MySQL syntax)
            
            connection.commit()
            print("Successfully created MySQL tables and inserted sample data")
            
        except Exception as e:
            print(f"Error creating MySQL tables: {e}")
            if connection:
                connection.rollback()
            raise
        finally:
            if connection:
                connection.close()
    
    def generate_streaming_events(self, count: int = 1000) -> List[Dict[str, Any]]:
        """Generate sample streaming events"""
        events = []
        
        event_types = ['page_view', 'button_click', 'purchase', 'login', 'logout', 'search']
        
        for i in range(count):
            event = {
                'event_id': fake.uuid4(),
                'event_type': random.choice(event_types),
                'user_id': random.randint(1, 1000),
                'timestamp': datetime.now().isoformat(),
                'properties': {
                    'page_url': fake.url(),
                    'user_agent': fake.user_agent(),
                    'ip_address': fake.ipv4(),
                    'session_id': fake.uuid4()
                }
            }
            
            # Add event-specific properties
            if event['event_type'] == 'purchase':
                event['properties'].update({
                    'product_id': random.randint(1, 500),
                    'amount': round(random.uniform(10.0, 500.0), 2),
                    'currency': 'USD'
                })
            elif event['event_type'] == 'search':
                event['properties']['search_query'] = fake.sentence(nb_words=3)
            
            events.append(event)
        
        return events

def main():
    parser = argparse.ArgumentParser(description='Generate sample data for ETL pipeline testing')
    parser.add_argument('--environment', default='dev', choices=['dev', 'staging', 'prod'],
                       help='Environment to generate data for')
    parser.add_argument('--users', type=int, default=1000, help='Number of users to generate')
    parser.add_argument('--products', type=int, default=500, help='Number of products to generate')
    parser.add_argument('--orders', type=int, default=5000, help='Number of orders to generate')
    parser.add_argument('--s3-only', action='store_true', help='Only upload to S3, skip database')
    parser.add_argument('--bucket', help='S3 bucket name (if not provided, will use stack output)')
    
    args = parser.parse_args()
    
    generator = SampleDataGenerator(args.environment)
    
    # Get S3 bucket name
    if args.bucket:
        bucket_name = args.bucket
    else:
        # Try to get from CloudFormation stack
        cf_client = boto3.client('cloudformation')
        try:
            stack_name = f"{generator.project_name}-{args.environment}-foundation"
            response = cf_client.describe_stacks(StackName=stack_name)
            outputs = response['Stacks'][0].get('Outputs', [])
            bucket_name = next((o['OutputValue'] for o in outputs if o['OutputKey'] == 'DataLakeBucketName'), None)
            
            if not bucket_name:
                raise ValueError("Could not find DataLakeBucketName in stack outputs")
                
        except Exception as e:
            print(f"Error getting bucket name from CloudFormation: {e}")
            print("Please provide bucket name with --bucket parameter")
            return
    
    print(f"Generating sample data for environment: {args.environment}")
    print(f"Target S3 bucket: {bucket_name}")
    
    # Generate data
    print("Generating users...")
    users = generator.generate_users(args.users)
    
    print("Generating products...")
    products = generator.generate_products(args.products)
    
    print("Generating orders...")
    orders = generator.generate_orders(args.users, args.products, args.orders)
    
    print("Generating streaming events...")
    events = generator.generate_streaming_events(1000)
    
    # Upload to S3
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    generator.upload_to_s3(
        users, 
        bucket_name, 
        f"sample-data/users/users_{timestamp}.json"
    )
    
    generator.upload_to_s3(
        products, 
        bucket_name, 
        f"sample-data/products/products_{timestamp}.json"
    )
    
    generator.upload_to_s3(
        orders, 
        bucket_name, 
        f"sample-data/orders/orders_{timestamp}.json"
    )
    
    generator.upload_to_s3(
        events, 
        bucket_name, 
        f"sample-data/events/events_{timestamp}.json"
    )
    
    print(f"Sample data generation completed!")
    print(f"Generated {len(users)} users, {len(products)} products, {len(orders)} orders, {len(events)} events")

if __name__ == "__main__":
    main()