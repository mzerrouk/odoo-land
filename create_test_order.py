from odoo import api, SUPERUSER_ID
import odoo

def create_test_order():
    env = api.Environment(odoo.registry(odoo.tools.config['db_name']).cursor(), SUPERUSER_ID, {})
    
    vendor = env.ref('facility_managementV2.vendor_test_standard')
    location = env.ref('facility_managementV2.location_test_floor_1')
    asset = env.ref('facility_managementV2.asset_test_ac')
    tenant = env.ref('facility_managementV2.tenant_test')
    
    # Create Request
    request = env['facility.maintenance.request'].create({
        'description': 'Test Order for Portal Verification',
        'tenant_id': tenant.id,
        'location_id': location.id,
        'asset_id': asset.id,
        'state': 'approved',
    })
    
    # Create Order
    order = env['facility.maintenance.order'].create({
        'request_id': request.id,
        'vendor_id': vendor.id,
        'state': 'vendor_notified',
        'scheduled_date': '2026-04-05',
    })
    
    env.cr.commit()
    print(f"Created Order: {order.name} (ID: {order.id})")

if __name__ == "__main__":
    create_test_order()
