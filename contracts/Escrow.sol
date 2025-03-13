// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IERC20Metadata {
    function decimals() external returns (uint8);
}

contract HyperBoreEscrow {
    address public daoMultisig;
    uint256 public nextEscrowId;
    uint8 private constant DAO_FEE_PERCENT = 5; // 5% cut for the DAO in disputed cases
    
    /**
        * Status Lookup Table
        * 0 - Default, funds are locked and not in dispute
        * 1 - Released, payee may recover funds from contract
        * 2 - Returned, payer may recover funds from contract
        * 3 - Disputed, DAO multisig may update status
        * 4 - Disputed to Released, payee may recover funds, shares funds with DAO multisig
        * 5 - Disputed to Returned, payer may recover funds, shares funds with DAO multisig
    */

    struct Escrow {
        address payer;
        address payee;
        address token; // ERC-20 token being escrowed (address(0) for ETH)
        uint256 amount;
        uint8 status;
        uint256 deadline; // When the payer can no longer release funds
        uint256 daoDeadline; // When the DAO must rule by
        uint256 createdAt; // Timestamp of escrow creation
    }

    mapping(uint256 => Escrow) public escrows;

    event EscrowCreated(uint256 indexed escrowId, address indexed payer, address indexed payee, uint256 amount, address token);
    event FundsWithdrawn(uint256 indexed escrowId, address recipient, uint256 amount);
    event DisputeRaised(uint256 indexed escrowId);
    event DisputeResolved(uint256 indexed escrowId, uint8 newStatus);
    event DAOAddressChanged(address indexed daoMultisig);

    constructor(address _daoMultisig) {
        require(_daoMultisig != address(0), "Invalid multisig address");
        daoMultisig = _daoMultisig;
    }

    function updateDAOMultisig(address _newMultisig) external {
        require(msg.sender == daoMultisig, "Uninvolved user");
        require(_newMultisig != address(0), "Can't burn contract");
        daoMultisig = _newMultisig;
       emit DAOAddressChanged(_newMultisig);
    }

    function createEscrow(
        address _payee,
        address _token,
        uint256 _amount,
        uint256 _deadline,
        uint256 _daoDeadline
    ) external payable {
        require(_payee != address(0), "Invalid payee address");
        require(_deadline > block.timestamp, "Invalid deadline");
        require(_daoDeadline > _deadline, "Invalid DAO deadline");
        
        if (_token == address(0)) {
            require(_amount >= 1e16, "Escrow amount too small"); // 0.01 ETH Minimum for ETH
            require(msg.value == _amount, "Incorrect ETH deposit");
        } else {
            require(msg.value == 0, "ETH not needed for token escrow");
            uint8 decimals = IERC20Metadata(_token).decimals();
            uint256 coinMinAmount = decimals >= 2 ? 10 ** (decimals - 2) : 1; // Ensure safe calculation
            require(_amount >= coinMinAmount, "Escrow amount too small");
            require(IERC20(_token).transferFrom(msg.sender, address(this), _amount), "Token transfer failed");
        }

        escrows[nextEscrowId] = Escrow({
            payer: msg.sender,
            payee: _payee,
            token: _token,
            amount: _amount,
            status: 0, // Default status
            deadline: _deadline,
            daoDeadline: _daoDeadline,
            createdAt: block.timestamp
        });

        emit EscrowCreated(nextEscrowId, msg.sender, _payee, _amount, _token);
        nextEscrowId++;
    }

    function dispute(uint256 _escrowId) external {
        Escrow storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.payer, "Only the payer can raise a dispute");
        require(escrow.status == 0, "Escrow must be active to dispute");
        require(block.timestamp <= escrow.deadline, "Cannot dispute after deadline");
        
        escrow.status = 3;
        emit DisputeRaised(_escrowId);
    }

    /**
     * Requiring the dao to elevate disputes is a show
     * of trust in the users of our escrow - word is bond,
     * disputes should be exceedingly rare.
     */

    function daoDispute(uint256 _escrowId) external {
        Escrow storage escrow = escrows[_escrowId];
        require(msg.sender == daoMultisig, "Only the DAO can do a DAO Dispute");
        require(escrow.status == 0, "Escrow must be active to dispute");
        require(block.timestamp >= escrow.deadline, "Deadline must have passed for DAO to resolve");
        escrow.status = 3;
        emit DisputeRaised(_escrowId);
    }

    function resolveDispute(uint256 _escrowId, uint8 _resolutionStatus) external {
        require(msg.sender == daoMultisig, "Only the DAO can resolve disputes");
        require(_resolutionStatus == 4 || _resolutionStatus == 5, "Invalid resolution status");
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.status == 3, "Escrow must be in disputed state");
        require(block.timestamp <= escrow.daoDeadline, "DAO ruling deadline has passed");
        
        escrow.status = _resolutionStatus;
        emit DisputeResolved(_escrowId, _resolutionStatus);
    }

    function withdraw(uint256 _escrowId) external payable {
        Escrow storage escrow = escrows[_escrowId];
        require(msg.sender == daoMultisig || msg.sender == escrow.payer || msg.sender == escrow.payee, "Uninvolved with escrow");
        require(escrow.status > 0 && escrow.status < 6, "Invalid escrow status");
        if (escrow.status == 3) {
            require(block.timestamp >= escrow.daoDeadline, "DAO ruling ongoing");
        }
        address recipient;
        uint256 amount = escrow.amount;
        uint256 daoFee = (amount * DAO_FEE_PERCENT) / 100;
        if (escrow.status == 1) {
            recipient = escrow.payee;
        }
        if (escrow.status == 2 || escrow.status == 3) {
            recipient = escrow.payer;
        }
        if (escrow.status == 4) {
            recipient = escrow.payee;
            amount = escrow.amount - daoFee;
        }
        if (escrow.status == 5) {
            recipient = escrow.payer;
            amount = escrow.amount - daoFee;
        }
        
        if (escrow.token == address(0)) {
            // payment is in ETH
            payable(daoMultisig).transfer(daoFee);
            payable(recipient).transfer(amount);
        } else {
            require(IERC20(escrow.token).transfer(daoMultisig, daoFee), "Failed to pay resolution fee");
            require(IERC20(escrow.token).transfer(recipient, amount), "Failed to release funds");
        }
        emit FundsWithdrawn(_escrowId, recipient, amount);
        delete escrows[_escrowId];
    }
}
