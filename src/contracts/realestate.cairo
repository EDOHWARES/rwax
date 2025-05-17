#[starknet::contract]
mod RealEstateFractionalOwnership {
    use rwax::interfaces::irealestate::IRealEstateFractionalOwnership;
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address,
        storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess},
    };
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
        management_fee_percent: u8, // Out of 100
        // Governance
        proposals: Map<u256, Proposal>,
        proposal_count: u256,
        decision_threshold: u8, // Percentage needed to approve (e.g. 51)
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
    fn constructor(
        ref self: ContractState, uri: felt252, management_fee_percent: u8, decision_threshold: u8,
    ) {
        self.erc1155.initializer("");
        assert(management_fee_percent <= 20, 'Fee too high');
        assert(decision_threshold > 50 && decision_threshold <= 100, 'Invalid threshold');

        // Initialize contract parameters
        self.management_fee_percent.write(management_fee_percent);
        self.decision_threshold.write(decision_threshold);
        self.property_count.write(0);
        self.proposal_count.write(0);
    }

    #[abi(embed_v0)]
    impl RealEstateFractionalOwnershipImpl of IRealEstateFractionalOwnership<ContractState> {
        fn create_proposal(
            ref self: ContractState,
            property_id: u256,
            description: felt252,
            value: u256,
            recipient: ContractAddress,
            voting_period: u64,
        ) {
            // Only property manager or significant shareholders can create proposals
            let caller = get_caller_address();
            let manager = self.property_managers.read(property_id);
            let balance = self.erc1155.balance_of(caller, property_id);
            let details = self.property_details.read(property_id);

            assert(
                caller == manager || balance > details.total_shares / 10_u256,
                'Not authorized to propose',
            );

            let proposal_id = self.proposal_count.read();
            let voting_end_time = get_block_timestamp() + voting_period;

            let proposal = Proposal {
                property_id,
                description,
                value,
                recipient,
                voting_end_time,
                executed: false,
                votes_for: 0_u256,
                votes_against: 0_u256,
            };

            // Store proposal
            self.proposals.write(proposal_id, proposal);
            self.proposal_count.write(proposal_id + 1);

            // Emit event
            self
                .emit(
                    ProposalCreated {
                        proposal_id, property_id, creator: caller, description, voting_end_time,
                    },
                );
        }

        fn purchase_property(ref self: ContractState, property_id: u256) {
            assert(self.for_sale.read(property_id), 'Property not for sale');

            let details = self.property_details.read(property_id);
            let sale_price = self.sale_price.read(property_id);
            let caller = get_caller_address();
            self.emit(PropertySold { property_id, buyer: caller, sale_price });

            // Mark property as no longer for sale
            self.for_sale.write(property_id, false);
        }

        fn add_property(
            ref self: ContractState,
            property_address: felt252,
            property_description: felt252,
            property_value: u256,
            property_image_uri: felt252,
            total_shares: u256,
            share_price: u256,
            initial_owner: ContractAddress,
            property_manager: ContractAddress,
        ) {
            // Only contract owner can add properties
            self.src5.assert_only_owner();

            let property_id = self.property_count.read();

            // Create property details
            let details = PropertyDetails {
                property_id,
                property_address,
                property_description,
                property_value,
                property_image_uri,
                total_shares,
                share_price,
            };

            // Mint all shares to initial owner
            self.erc1155.mint(initial_owner, property_id, total_shares, array![].span());

            // Store property details and manager
            self.property_details.write(property_id, details);
            self.property_managers.write(property_id, property_manager);

            // Increment property count
            self.property_count.write(property_id + 1);

            // Emit event
            self.emit(PropertyAdded { property_id, property_address, total_shares });
        }

        fn get_proposal_details(self: @TContractState, proposal_id: u256) -> Proposal {
            // Retrieve proposal details
            self.proposals.read(proposal_id);
        }

        fn distribute_rental_income(ref self: ContractState, property_id: u256, amount: u256) {
            // Only property manager can distribute income
            let manager = self.property_managers.read(property_id);
            assert(get_caller_address() == manager, 'Only property manager');
            
            let details = self.property_details.read(property_id);
            let total_shares = details.total_shares;
            
            // Calculate management fee
            let fee_percent = self.management_fee_percent.read();
            let fee = amount * u256::from(fee_percent) / 100_u256;
            let distributable = amount - fee;
            
            // Calculate income per share
            let income_per_share = distributable / total_shares;
            
            // Update tracking
            self.total_rental_income.write(property_id, self.total_rental_income.read(property_id) + amount);
            self.rental_income_per_share.write(property_id, 
                self.rental_income_per_share.read(property_id) + income_per_share);
            
            // Emit event
            self.emit(RentalIncomeDistributed {
                property_id,
                amount: distributable,
                timestamp: get_block_timestamp()
            });
      }

        fn execute_proposal(ref self: ContractState, proposal_id: u256) {
            let mut proposal = self.proposals.read(proposal_id);

            // Check proposal hasn't been executed
            assert(!proposal.executed, 'Already executed');

            // Check voting period has ended
            assert(get_block_timestamp() >= proposal.voting_end_time, 'Voting ongoing');

            // Check threshold met
            let total_votes = proposal.votes_for + proposal.votes_against;
            let threshold = self.decision_threshold.read();
            let percentage_for = (proposal.votes_for * 100_u256) / total_votes;
            assert(percentage_for >= u256::from(threshold), 'Threshold not met');

            // Mark as executed
            proposal.executed = true;
            self.proposals.write(proposal_id, proposal);

            // In a real implementation, execute the proposal action here
            // For now we just emit an event
            self.emit(ProposalExecuted { proposal_id });
        }

        fn cast_vote(ref self: ContractState, proposal_id: u256, support: bool) {
            let caller = get_caller_address();
            let mut proposal = self.proposals.read(proposal_id);

            // Check voting period hasn't ended
            assert(get_block_timestamp() < proposal.voting_end_time, 'Voting ended');

            // Check voter has shares
            let balance = self.erc1155.balance_of(caller, proposal.property_id);
            assert(balance > 0, 'No shares to vote with');

            // Update vote counts
            if support {
                proposal.votes_for += balance;
            } else {
                proposal.votes_against += balance;
            }

            // Save updated proposal
            self.proposals.write(proposal_id, proposal);

            // Emit event
            self
                .emit(
                    VoteCast {
                        proposal_id, voter: caller, supports: support, voting_power: balance,
                    },
                );
        }

        fn get_proposal_details(self: @ContractState, proposal_id: u256) -> Proposal {
            self.proposals.read(proposal_id)
        }

        fn create_proposal(
            ref self: ContractState, 
            property_id: u256,
            description: felt252, 
            value: u256,
            recipient: ContractAddress,
            voting_period: u64
        ) {
            // Only property manager or significant shareholders can create proposals
            let caller = get_caller_address();
            let manager = self.property_managers.read(property_id);
            let balance = self.erc1155.balance_of(caller, property_id);
            let details = self.property_details.read(property_id);
            
            assert(
                caller == manager || balance > details.total_shares / 10_u256,
                'Not authorized to propose'
            );
            
            let proposal_id = self.proposal_count.read();
            let voting_end_time = get_block_timestamp() + voting_period;
            
            let proposal = Proposal {
                property_id,
                description,
                value,
                recipient,
                voting_end_time,
                executed: false,
                votes_for: 0_u256,
                votes_against: 0_u256
            };
            
            // Store proposal
            self.proposals.write(proposal_id, proposal);
            self.proposal_count.write(proposal_id + 1);
            
            // Emit event
            self.emit(ProposalCreated {
                proposal_id,
                property_id,
                creator: caller,
                description,
                voting_end_time
            });
        }
}
