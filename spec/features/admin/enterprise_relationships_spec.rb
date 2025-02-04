require 'spec_helper'

feature '
  As an Administrator
  I want to manage relationships between enterprises
', js: true do
  include AuthenticationWorkflow
  include WebHelper

  context "as a site administrator" do
    before { quick_login_as_admin }

    scenario "listing relationships" do
      # Given some enterprises with relationships
      e1, e2, e3, e4 = create(:enterprise), create(:enterprise), create(:enterprise), create(:enterprise)
      create(:enterprise_relationship, parent: e1, child: e2, permissions_list: [:add_to_order_cycle])
      create(:enterprise_relationship, parent: e2, child: e3, permissions_list: [:manage_products])
      create(:enterprise_relationship, parent: e3, child: e4, permissions_list: [:add_to_order_cycle, :manage_products])

      # When I go to the relationships page
      visit spree.admin_path
      click_link 'Enterprises'
      click_link 'Permissions'

      # Then I should see the relationships
      within('table#enterprise-relationships') do
        expect(page).to have_relationship e1, e2, ['to add to order cycle']
        expect(page).to have_relationship e2, e3, ['to manage products']
        expect(page).to have_relationship e3, e4,
          ['to add to order cycle', 'to manage products']
      end
    end

    scenario "creating a relationship" do
      e1 = create(:enterprise, name: 'One')
      e2 = create(:enterprise, name: 'Two')

      visit admin_enterprise_relationships_path
      select2_select 'One', from: 'enterprise_relationship_parent_id'

      check 'to add to order cycle'
      check 'to manage products'
      uncheck 'to manage products'
      check 'to edit profile'
      check 'to add products to inventory'
      select2_select 'Two', from: 'enterprise_relationship_child_id'
      click_button 'Create'

      # Wait for row to appear since have_relationship doesn't wait
      expect(page).to have_selector 'tr', count: 2
      expect(page).to have_relationship e1, e2, ['to add to order cycle', 'to add products to inventory', 'to edit profile']
      er = EnterpriseRelationship.where(parent_id: e1, child_id: e2).first
      expect(er).to be_present
      expect(er.permissions.map(&:name)).to match_array ['add_to_order_cycle', 'edit_profile', 'create_variant_overrides']
    end

    scenario "attempting to create a relationship with invalid data" do
      e1 = create(:enterprise, name: 'One')
      e2 = create(:enterprise, name: 'Two')
      create(:enterprise_relationship, parent: e1, child: e2)

      expect do
        # When I attempt to create a duplicate relationship
        visit admin_enterprise_relationships_path
        select2_select 'One', from: 'enterprise_relationship_parent_id'
        select2_select 'Two', from: 'enterprise_relationship_child_id'
        click_button 'Create'

        # Then I should see an error message
        expect(page).to have_content "That relationship is already established."
      end.to change(EnterpriseRelationship, :count).by(0)
    end

    scenario "deleting a relationship" do
      e1 = create(:enterprise, name: 'One')
      e2 = create(:enterprise, name: 'Two')
      er = create(:enterprise_relationship, parent: e1, child: e2, permissions_list: [:add_to_order_cycle])

      visit admin_enterprise_relationships_path
      expect(page).to have_relationship e1, e2, ['to add to order cycle']

      accept_alert do
        first("a.delete-enterprise-relationship").click
      end

      expect(page).not_to have_relationship e1, e2
      expect(EnterpriseRelationship.where(id: er.id)).to be_empty
    end
  end

  context "as an enterprise user" do
    let!(:d1) { create(:distributor_enterprise) }
    let!(:d2) { create(:distributor_enterprise) }
    let!(:d3) { create(:distributor_enterprise) }
    let(:enterprise_user) { create_enterprise_user( enterprises: [d1] ) }

    let!(:er1) { create(:enterprise_relationship, parent: d1, child: d2) }
    let!(:er2) { create(:enterprise_relationship, parent: d2, child: d1) }
    let!(:er3) { create(:enterprise_relationship, parent: d2, child: d3) }

    before { quick_login_as enterprise_user }

    scenario "enterprise user can only see relationships involving their enterprises" do
      visit admin_enterprise_relationships_path

      expect(page).to     have_relationship d1, d2
      expect(page).to     have_relationship d2, d1
      expect(page).not_to have_relationship d2, d3
    end

    scenario "enterprise user can only add their own enterprises as parent" do
      visit admin_enterprise_relationships_path
      expect(page).to have_select2 'enterprise_relationship_parent_id', options: ['', d1.name]
      expect(page).to have_select2 'enterprise_relationship_child_id', with_options: ['', d1.name, d2.name, d3.name]
    end
  end

  private

  def have_relationship(parent, child, perms = [])
    perms = perms.join(' ')

    have_table_row [parent.name, 'permits', child.name, perms, '']
  end
end
