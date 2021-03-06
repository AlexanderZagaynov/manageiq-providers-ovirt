describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  let(:ip_address) { '192.168.1.105' }

  before(:each) do
    _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
    @ems = FactoryGirl.create(:ems_redhat, :zone => zone, :hostname => "192.168.1.105", :ipaddress => "192.168.1.105",
                              :port => 8443)
    @ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4
    allow_any_instance_of(@ovirt_service)
    allow_any_instance_of(@ovirt_service)
      .to receive(:collect_external_network_providers).and_return(load_response_mock_for('external_network_providers'))
    @ems.update_authentication(:default => {:userid => "admin@internal", :password => "engine"})
    @ems.default_endpoint.path = "/ovirt-engine/api"
    allow(@ems).to receive(:supported_api_versions).and_return(%w(3 4))
    allow(@ems).to receive(:resolve_ip_address).with(ip_address).and_return(ip_address)
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
  end

  it ".ems_type" do
    expect(described_class.ems_type).to eq(:rhevm)
  end

  require 'yaml'
  def load_response_mock_for(filename)
    prefix = described_class.name.underscore
    YAML.load_file(File.join('spec', 'models', prefix, 'target_response_yamls', filename + '.yml'))
  end

  before(:each) do
    @inventory_wrapper_class = ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4
    allow_any_instance_of(@inventory_wrapper_class).to receive(:api).and_return("4.2.0_master")
    allow_any_instance_of(@inventory_wrapper_class).to receive(:service)
      .and_return(OpenStruct.new(:version_string => '4.2.0_master'))

    @root = FactoryGirl.create(:ems_folder,
                               :ext_management_system => @ems,
                               :uid_ems               => 'root_dc',
                               :name                  => "Datacenters")

    @host_folder = FactoryGirl.create(:ems_folder,
                                      :ext_management_system => @ems,
                                      :uid_ems               => "00000001-0001-0001-0001-000000000311_host",
                                      :name                  => "host")

    @vm_folder = FactoryGirl.create(:ems_folder,
                                    :ext_management_system => @ems,
                                    :uid_ems               => "00000001-0001-0001-0001-000000000311_vm",
                                    :name                  => "vm")

    @dc = FactoryGirl.create(:datacenter,
                             :ems_ref               => "/api/datacenters/00000001-0001-0001-0001-000000000311",
                             :ext_management_system => @ems,
                             :name                  => "Default",
                             :uid_ems               => "00000001-0001-0001-0001-000000000311")

    @cluster = FactoryGirl.create(:ems_cluster,
                                  :ems_ref               => "/api/clusters/00000002-0002-0002-0002-00000000017a",
                                  :uid_ems               => "00000002-0002-0002-0002-00000000017a",
                                  :ext_management_system => @ems,
                                  :name                  => "Default")

    @rp = FactoryGirl.create(:resource_pool,
                             :ext_management_system => @ems,
                             :name                  => "Default for Cluster Default",
                             :uid_ems               => "00000002-0002-0002-0002-00000000017a_respool")

    @storage = FactoryGirl.create(:storage,
                                  :ems_ref  => "/api/storagedomains/6cc26c9d-e1a7-43ba-95d3-c744442c7500",
                                  :location => "192.168.1.107:/export/data")

    @disk = FactoryGirl.create(:disk,
                               :storage  => @storage,
                               :filename => "c413aff6-e988-4830-8b24-f74af66ced5a")
    @hardware = FactoryGirl.create(:hardware,
                                   :disks => [@disk])

    @vm = FactoryGirl.create(:vm_redhat,
                             :ext_management_system => @ems,
                             :uid_ems               => "3a697bd0-7cea-42a1-95ef-fd292fcee721",
                             :ems_cluster_id        => @cluster.id,
                             :ems_ref               => "/api/vms/3a697bd0-7cea-42a1-95ef-fd292fcee721",
                             :storage               => @storage,
                             :storages              => [@storage],
                             :hardware              => @hardware)
  end

  it "should refresh a vm" do
    allow_any_instance_of(@inventory_wrapper_class)
      .to receive(:collect_clusters).and_return(load_response_mock_for('clusters'))
    allow_any_instance_of(@inventory_wrapper_class)
      .to receive(:collect_datacenters).and_return(load_response_mock_for('datacenters'))
    allow_any_instance_of(@inventory_wrapper_class)
      .to receive(:collect_vm_by_uuid).and_return(load_response_mock_for('vms'))
    allow_any_instance_of(@inventory_wrapper_class)
      .to receive(:collect_storage).and_return(load_response_mock_for('storages'))
    allow_any_instance_of(@inventory_wrapper_class)
      .to receive(:search_templates).and_return(load_response_mock_for('templates'))

    EmsRefresh.refresh(@vm)

    assert_table_counts
    assert_vm(@vm, @storage)
    assert_vm_rels(@vm, @hardware, @storage)
    assert_cluster(@vm)
    assert_storage(@storage, @vm)
  end

  it "should collect a vm" do
    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})

    cluster_service = double("cluster_service")
    allow(cluster_service).to receive(:get).and_return(load_response_mock_for('cluster'))
    allow_any_instance_of(OvirtSDK4::ClustersService).to receive(:cluster_service).and_return(cluster_service)
    allow_any_instance_of(OvirtSDK4::ClustersService).to receive(:list).and_return(load_response_mock_for('clusters'))

    data_center_service = double("data_center_service")
    allow(data_center_service).to receive(:get).and_return(load_response_mock_for('datacenter'))
    allow_any_instance_of(OvirtSDK4::DataCentersService).to receive(:data_center_service).and_return(data_center_service)

    storage_domain_service = double("storage_domain_service")
    allow(storage_domain_service).to receive(:get).and_return(load_response_mock_for('storage'))
    allow_any_instance_of(OvirtSDK4::StorageDomainsService).to receive(:storage_domain_service).and_return(storage_domain_service)

    collector_class = ManageIQ::Providers::Redhat::Inventory::Collector
    allow_any_instance_of(collector_class).to receive(:collect_attached_disks).and_return(load_response_mock_for('disks'))
    allow_any_instance_of(collector_class).to receive(:collect_vm_devices).and_return([])
    allow_any_instance_of(collector_class).to receive(:collect_nics).and_return(load_response_mock_for('nics'))
    allow_any_instance_of(collector_class).to receive(:collect_snapshots).and_return(load_response_mock_for('snapshots'))
    target_collector_class = ManageIQ::Providers::Redhat::Inventory::Collector::TargetCollection
    allow_any_instance_of(target_collector_class).to receive(:templates).and_return(load_response_mock_for('templates'))
    allow_any_instance_of(target_collector_class).to receive(:vms).and_return(load_response_mock_for('vms'))

    @rp.with_relationship_type("ems_metadata") { @rp.add_child(@vm) }
    @vm.with_relationship_type("ems_metadata") { @vm.set_parent @rp }

    @cluster.with_relationship_type("ems_metadata") { @cluster.add_child @rp }
    @rp.with_relationship_type("ems_metadata") { @rp.set_parent @cluster }

    @vm_folder.with_relationship_type("ems_metadata") { @vm_folder.add_child @vm }
    @host_folder.with_relationship_type("ems_metadata") { @host_folder.add_child @cluster }
    @dc.with_relationship_type("ems_metadata") { @dc.add_child @host_folder }
    @dc.with_relationship_type("ems_metadata") { @dc.add_child @vm_folder }

    @root.with_relationship_type("ems_metadata") { @root.add_child @dc }
    @ems.add_child @root

    EmsRefresh.refresh(@vm)

    assert_table_counts
    assert_vm(@vm, @storage)
    assert_vm_rels(@vm, @hardware, @storage)
    assert_cluster(@vm)
    assert_storage(@storage, @vm)
  end

  def assert_table_counts
    expect(ExtManagementSystem.count).to eq(2)
    expect(EmsCluster.count).to eq(1)
    expect(ResourcePool.count).to eq(1)
    expect(Vm.count).to eq(1)
    expect(Storage.count).to eq(1)
    expect(Disk.count).to eq(1)
    expect(GuestDevice.count).to eq(1)
    expect(Hardware.count).to eq(1)
    expect(OperatingSystem.count).to eq(1)
    expect(Snapshot.count).to eq(1)
    expect(Datacenter.count).to eq(1)

    expect(Relationship.count).to eq(9)
    expect(MiqQueue.count).to eq(5)
  end

  def assert_vm(vm, storage)
    vm.reload
    expect(vm).to have_attributes(
      :template               => false,
      :ems_ref                => "/api/vms/3a697bd0-7cea-42a1-95ef-fd292fcee721",
      :ems_ref_obj            => "/api/vms/3a697bd0-7cea-42a1-95ef-fd292fcee721",
      :uid_ems                => "3a697bd0-7cea-42a1-95ef-fd292fcee721",
      :vendor                 => "redhat",
      :raw_power_state        => "down",
      :power_state            => "off",
      :connection_state       => "connected",
      :name                   => "new",
      :format                 => nil,
      :version                => nil,
      :description            => nil,
      :location               => "3a697bd0-7cea-42a1-95ef-fd292fcee721.ovf",
      :config_xml             => nil,
      :autostart              => nil,
      :host_id                => nil,
      :last_sync_on           => nil,
      :storage_id             => storage.id,
      :last_scan_on           => nil,
      :last_scan_attempt_on   => nil,
      :retires_on             => nil,
      :retired                => nil,
      :boot_time              => nil,
      :tools_status           => nil,
      :standby_action         => nil,
      :previous_state         => "up",
      :last_perf_capture_on   => nil,
      :registered             => nil,
      :busy                   => nil,
      :smart                  => nil,
      :memory_reserve         => 1024,
      :memory_reserve_expand  => nil,
      :memory_limit           => nil,
      :memory_shares          => nil,
      :memory_shares_level    => nil,
      :cpu_reserve            => nil,
      :cpu_reserve_expand     => nil,
      :cpu_limit              => nil,
      :cpu_shares             => nil,
      :cpu_shares_level       => nil,
      :cpu_affinity           => nil,
      :ems_created_on         => nil,
      :evm_owner_id           => nil,
      :linked_clone           => nil,
      :fault_tolerance        => nil,
      :type                   => "ManageIQ::Providers::Redhat::InfraManager::Vm",
      :ems_cluster_id         => @cluster.id,
      :retirement_warn        => nil,
      :retirement_last_warn   => nil,
      :vnc_port               => nil,
      :flavor_id              => nil,
      :availability_zone_id   => nil,
      :cloud                  => false,
      :retirement_state       => nil,
      :cloud_network_id       => nil,
      :cloud_subnet_id        => nil,
      :cloud_tenant_id        => nil,
      :publicly_available     => nil,
      :orchestration_stack_id => nil,
      :retirement_requester   => nil,
      :resource_group_id      => nil,
      :deprecated             => nil,
      :storage_profile_id     => nil
    )

    expect(vm.ext_management_system).to eq(@ems)
    expect(vm.ems_cluster).to eq(@cluster)
    expect(vm.storage).to eq(storage)
  end

  def assert_vm_rels(vm, hardware, storage)
    expect(vm.snapshots.size).to eq(1)
    snapshot = vm.snapshots.first
    expect(snapshot).to have_attributes(
      :uid               => "4af35c92-7c6e-4c23-b25e-e05cb29bed49",
      :parent_uid        => nil,
      :uid_ems           => "4af35c92-7c6e-4c23-b25e-e05cb29bed49",
      :name              => "Active VM",
      :description       => "Active VM",
      :current           => 1,
      :total_size        => nil,
      :filename          => nil,
      :disks             => [],
      :parent_id         => nil,
      :vm_or_template_id => vm.id,
      :ems_ref           => nil
    )

    expect(vm.hardware).to eq(hardware)
    expect(vm.hardware).to have_attributes(
      :guest_os             => "other",
      :guest_os_full_name   => nil,
      :bios                 => nil,
      :cpu_cores_per_socket => 1,
      :cpu_total_cores      => 1,
      :cpu_sockets          => 1,
      :annotation           => "12345",
      :memory_mb            => 1024,
      :config_version       => nil,
      :virtual_hw_version   => nil,
      :bios_location        => nil,
      :time_sync            => nil,
      :vm_or_template_id    => vm.id,
      :host_id              => nil,
      :cpu_speed            => nil,
      :cpu_type             => nil,
      :size_on_disk         => nil,
      :manufacturer         => "",
      :model                => "",
      :number_of_nics       => nil,
      :cpu_usage            => nil,
      :memory_usage         => nil,
      :vmotion_enabled      => nil,
      :disk_free_space      => nil,
      :disk_capacity        => nil,
      :memory_console       => nil,
      :bitness              => nil,
      :virtualization_type  => nil,
      :root_device_type     => nil,
      :computer_system_id   => nil,
      :disk_size_minimum    => nil,
      :memory_mb_minimum    => nil
    )

    expect(vm.hardware.disks.size).to eq(1)
    disk = vm.hardware.disks.first
    expect(disk.storage).to eq(storage)
    expect(disk).to have_attributes(
      :device_name        => "new_Disk1",
      :device_type        => "disk",
      :location           => "0",
      :filename           => "c413aff6-e988-4830-8b24-f74af66ced5a",
      :hardware_id        => hardware.id,
      :mode               => "persistent",
      :controller_type    => "virtio_scsi",
      :size               => 1.gigabyte,
      :free_space         => nil,
      :size_on_disk       => 0,
      :present            => true,
      :start_connected    => true,
      :auto_detect        => nil,
      :disk_type          => "thin",
      :storage_id         => storage.id,
      :backing_id         => nil,
      :backing_type       => nil,
      :storage_profile_id => nil,
      :bootable           => true
    )

    expect(vm.hardware.guest_devices.size).to eq(1)
    guest_device = vm.hardware.guest_devices.first
    expect(guest_device).to have_attributes(
      :device_name       => "nic1",
      :device_type       => "ethernet",
      :location          => nil,
      :filename          => nil,
      :hardware_id       => hardware.id,
      :mode              => nil,
      :controller_type   => "ethernet",
      :size              => nil,
      :free_space        => nil,
      :size_on_disk      => nil,
      :address           => "00:1a:4a:16:01:51",
      :switch_id         => nil,
      :lan_id            => nil,
      :model             => nil,
      :iscsi_name        => nil,
      :iscsi_alias       => nil,
      :present           => true,
      :start_connected   => true,
      :auto_detect       => nil,
      :uid_ems           => "bec92d4f-9b9e-462f-9cd4-7d6b99948a81",
      :chap_auth_enabled => nil
    )

    expect(vm.operating_system).not_to be_nil
    expect(vm.operating_system).to have_attributes(
      :name                  => nil,
      :product_name          => "other",
      :version               => nil,
      :build_number          => nil,
      :system_root           => nil,
      :distribution          => nil,
      :product_type          => nil,
      :service_pack          => nil,
      :productid             => nil,
      :vm_or_template_id     => vm.id,
      :host_id               => nil,
      :bitness               => nil,
      :product_key           => nil,
      :pw_hist               => nil,
      :max_pw_age            => nil,
      :min_pw_age            => nil,
      :min_pw_len            => nil,
      :pw_complex            => nil,
      :pw_encrypt            => nil,
      :lockout_threshold     => nil,
      :lockout_duration      => nil,
      :reset_lockout_counter => nil,
      :system_type           => "desktop",
      :computer_system_id    => nil,
      :kernel_version        => nil
    )
  end

  def assert_cluster(vm)
    @cluster.reload
    expect(@cluster).to have_attributes(
      :ems_ref                 => "/api/clusters/00000002-0002-0002-0002-00000000017a",
      :uid_ems                 => "00000002-0002-0002-0002-00000000017a",
      :name                    => "Default",
      :ha_enabled              => nil,
      :ha_admit_control        => nil,
      :ha_max_failures         => nil,
      :drs_enabled             => nil,
      :drs_automation_level    => nil,
      :drs_migration_threshold => nil,
      :last_perf_capture_on    => nil,
      :effective_cpu           => nil,
      :effective_memory        => nil,
      :type                    => nil
    )

    rp = vm.parent_resource_pool
    expect(@cluster.default_resource_pool).to eq(rp)
    expect(rp).to have_attributes(
      :ems_ref               => nil,
      :ems_ref_obj           => nil,
      :uid_ems               => "00000002-0002-0002-0002-00000000017a_respool",
      :name                  => "Default for Cluster Default",
      :memory_reserve        => nil,
      :memory_reserve_expand => nil,
      :memory_limit          => nil,
      :memory_shares         => nil,
      :memory_shares_level   => nil,
      :cpu_reserve           => nil,
      :cpu_reserve_expand    => nil,
      :cpu_limit             => nil,
      :cpu_shares            => nil,
      :cpu_shares_level      => nil,
      :is_default            => true,
      :vapp                  => nil
    )

    expect(vm.parent_datacenter).to have_attributes(
      :name    => "Default",
      :ems_ref => "/api/datacenters/00000001-0001-0001-0001-000000000311",
      :uid_ems => "00000001-0001-0001-0001-000000000311",
      :type    => "Datacenter",
      :hidden  => nil
    )
  end

  def assert_storage(storage, vm)
    storage.reload

    expect(vm.storage).to eq(storage)
    expect(storage).to have_attributes(
      :name                          => "data",
      :store_type                    => "NFS",
      :total_space                   => 922.gigabyte,
      :free_space                    => 791.gigabyte,
      :multiplehostaccess            => 1,
      :location                      => "192.168.1.107:/export/data",
      :last_scan_on                  => nil,
      :uncommitted                   => 908.gigabyte,
      :last_perf_capture_on          => nil,
      :directory_hierarchy_supported => nil,
      :thin_provisioning_supported   => nil,
      :raw_disk_mappings_supported   => nil,
      :master                        => true,
      :ems_ref                       => "/api/storagedomains/6cc26c9d-e1a7-43ba-95d3-c744442c7500",
      :storage_domain_type           => "data"
    )
  end
end
