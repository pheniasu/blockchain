// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

/// @title Land Registry
/// @notice Registers land parcels as NFT title deeds, tracks ownership transfers,
///         and exposes a full chain-of-custody history for each property.
/// @dev Each property is represented on-chain by a Property record and, in parallel,
///      by an ERC-721 token (the "title deed"). Document metadata (surveys, deeds)
///      is stored off-chain on IPFS and referenced via the token URI.
contract LandRegistry is ERC721URIStorage {

    /// @notice Address that deployed the contract and manages registrar permissions.
    address public admin;

    /// @notice Running counter used to assign sequential property IDs.
    uint256 public propertyCount;

    struct Property {
        uint256 id;
        string location;
        address owner;
        bool isRegistered;
    }

    /// @dev Property records, keyed by property ID.
    mapping(uint256 => Property) public properties;

    /// @dev Chronological list of every owner a property has had, keyed by property ID.
    mapping(uint256 => address[]) private ownershipHistory;

    /// @dev Addresses authorized to register new land parcels (role-based access control).
    mapping(address => bool) public isRegistrar;

    event LandRegistered(uint256 indexed propertyId, string location, address indexed owner, string tokenURI);
    event OwnershipTransferred(uint256 indexed propertyId, address indexed previousOwner, address indexed newOwner);
    event RegistrarAdded(address indexed registrar);
    event RegistrarRemoved(address indexed registrar);

    /// @dev Restricts a function to the admin or an authorized registrar.
    modifier onlyRegistrar() {
        require(isRegistrar[msg.sender] || msg.sender == admin, "LandRegistry: caller is not an authorized registrar");
        _;
    }

    /// @dev Restricts a function to the contract admin only.
    modifier onlyAdmin() {
        require(msg.sender == admin, "LandRegistry: caller is not the admin");
        _;
    }

    constructor() ERC721("LandTitleDeed", "DEED") {
        admin = msg.sender;
        isRegistrar[msg.sender] = true;
    }

    // ---------------------------------------------------------------------
    // Role-based access control
    // ---------------------------------------------------------------------

    /// @notice Grants registrar privileges to an address.
    /// @param registrar Address to authorize as a registrar.
    function addRegistrar(address registrar) external onlyAdmin {
        isRegistrar[registrar] = true;
        emit RegistrarAdded(registrar);
    }

    /// @notice Revokes registrar privileges from an address.
    /// @param registrar Address to remove as a registrar.
    function removeRegistrar(address registrar) external onlyAdmin {
        isRegistrar[registrar] = false;
        emit RegistrarRemoved(registrar);
    }

    // ---------------------------------------------------------------------
    // Land registration
    // ---------------------------------------------------------------------

    /// @notice Registers a new land parcel and mints its title deed NFT to the owner.
    /// @param location Human-readable description of the property (e.g. district, plot number).
    /// @param tokenURI IPFS URI pointing to the property's metadata document.
    /// @param owner Wallet address of the citizen who will hold the title deed.
    /// @return propertyId The ID assigned to the newly registered property.
    function registerLand(
        string calldata location,
        string calldata tokenURI,
        address owner
    ) external onlyRegistrar returns (uint256 propertyId) {
        require(owner != address(0), "LandRegistry: owner cannot be the zero address");

        propertyCount++;
        propertyId = propertyCount;

        properties[propertyId] = Property({
            id: propertyId,
            location: location,
            owner: owner,
            isRegistered: true
        });

        ownershipHistory[propertyId].push(owner);

        _safeMint(owner, propertyId);
        _setTokenURI(propertyId, tokenURI);

        emit LandRegistered(propertyId, location, owner, tokenURI);
    }

    // ---------------------------------------------------------------------
    // Ownership transfer
    // ---------------------------------------------------------------------

    /// @notice Transfers ownership of a registered property to a new owner.
    /// @dev Caller must be the current owner of the property's title deed NFT.
    /// @param propertyId ID of the property to transfer.
    /// @param newOwner Wallet address of the new owner.
    function transferOwnership(uint256 propertyId, address newOwner) external {
        require(properties[propertyId].isRegistered, "LandRegistry: property does not exist");
        require(ownerOf(propertyId) == msg.sender, "LandRegistry: caller does not own this property");
        require(newOwner != address(0), "LandRegistry: new owner cannot be the zero address");

        address previousOwner = properties[propertyId].owner;
        properties[propertyId].owner = newOwner;
        ownershipHistory[propertyId].push(newOwner);

        _transfer(msg.sender, newOwner, propertyId);

        emit OwnershipTransferred(propertyId, previousOwner, newOwner);
    }

    // ---------------------------------------------------------------------
    // Read-only lookups
    // ---------------------------------------------------------------------

    /// @notice Returns the full chronological list of owners for a property.
    /// @param propertyId ID of the property to query.
    /// @return An ordered array of owner addresses, from first registration to present.
    function getPropertyHistory(uint256 propertyId) external view returns (address[] memory) {
        require(properties[propertyId].isRegistered, "LandRegistry: property does not exist");
        return ownershipHistory[propertyId];
    }

    /// @notice Verifies whether a given address is the current registered owner of a property.
    /// @dev Pure read-only check — does not alter state. Used by clients to confirm a
    ///      claimed ownership before, e.g., accepting an offline transaction or contract.
    /// @param propertyId ID of the property to check.
    /// @param claimant Address whose ownership claim is being verified.
    /// @return True if `claimant` is the current registered owner of `propertyId`.
    function verifyOwnership(uint256 propertyId, address claimant) external view returns (bool) {
        require(properties[propertyId].isRegistered, "LandRegistry: property does not exist");
        return properties[propertyId].owner == claimant;
    }
}
