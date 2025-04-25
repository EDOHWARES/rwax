#[starknet::contract]
mod RealEstateFractionalOwnership {
    use rwax::interfaces::irealestate::IRealEstateFractionalOwnership;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess}};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc1155::{ERC1155Component, ERC1155HooksEmptyImpl};

    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // External
    #[abi(embed_v0)]
    impl ERC1155MixinImpl = ERC1155Component::ERC1155MixinImpl<ContractState>;

    // Internal
    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc1155: ERC1155Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,

        // Property registry
        property_count: u256,
        // property_details: Map<u256, PropertyDetails>,
        
        // Rental income tracking per property
        total_rental_income: Map<u256, u256>,
        claimed_rental_income: Map<(u256, ContractAddress), u256>,
        rental_income_per_share: Map<u256, u256>,
        
        // Management
        property_managers: Map<u256, ContractAddress>,
        management_fee_percent: u8,  // Out of 100
        
        // Governance
        // proposals: Map<u256, Proposal>,
        proposal_count: u256,
        decision_threshold: u8,  // Percentage needed to approve (e.g. 51)
        
        // Property sale status
        for_sale: Map<u256, bool>,
        sale_price: Map<u256, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC1155Event: ERC1155Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,

        // Custom events
        PropertyAdded: PropertyAdded,
        RentalIncomeDistributed: RentalIncomeDistributed,
        RentalIncomeClaimed: RentalIncomeClaimed,
        ProposalCreated: ProposalCreated,
        VoteCast: VoteCast,
        ProposalExecuted: ProposalExecuted,
        PropertyListed: PropertyListed,
        PropertySold: PropertySold,
    }


    #[derive(Drop, starknet::Event)]
    struct PropertyAdded {
        property_id: u256,
        property_address: felt252,
        total_shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RentalIncomeDistributed {
        property_id: u256,
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct RentalIncomeClaimed {
        property_id: u256,
        owner: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ProposalCreated {
        proposal_id: u256,
        property_id: u256,
        creator: ContractAddress,
        // proposal_type: ProposalType,
        description: felt252,
        voting_end_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct VoteCast {
        proposal_id: u256,
        voter: ContractAddress,
        supports: bool,
        voting_power: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ProposalExecuted {
        proposal_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PropertyListed {
        property_id: u256,
        sale_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PropertySold {
        property_id: u256,
        buyer: ContractAddress,
        sale_price: u256,
    }


    #[constructor]
    fn constructor(ref self: ContractState, uri: felt252,
        management_fee_percent: u8,
        decision_threshold: u8) {
        self.erc1155.initializer("");
        assert(management_fee_percent <= 20, 'Fee too high');
        assert(decision_threshold > 50 && decision_threshold <= 100, 'Invalid threshold');
        
        // Initialize contract parameters
        self.management_fee_percent.write(management_fee_percent);
        self.decision_threshold.write(decision_threshold);
        self.property_count.write(0);
        self.proposal_count.write(0);  
    }

    #[external(v0)]
    impl RealEstateFractionalOwnershipImpl of IRealEstateFractionalOwnership<ContractState> {
        
    }
}
