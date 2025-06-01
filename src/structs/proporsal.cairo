use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Proposal {
    pub property_id: u256,
    pub description: felt252,
    pub value: u256,
    pub recipient: ContractAddress,
    pub voting_end_time: u64,
    pub executed: bool,
    pub votes_for: u256,
    pub votes_against: u256,
}
