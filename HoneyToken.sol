pragma solidity ^0.4.15;


contract ERC20 {
    function totalSupply() external constant returns (uint256 _totalSupply);
    function balanceOf(address _owner) external constant returns (uint256 balance);
    function userTransfer(address _to, uint256 _value) external returns (bool success);
    function userTransferFrom(address _from, address _to, uint256 _value) external returns (bool success);
    function userApprove(address _spender, uint256 _old, uint256 _new) external returns (bool success);
    function allowance(address _owner, address _spender) external constant returns (uint256 remaining);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    
    function ERC20() internal {
    }
}

library SafeMath {
    uint256 constant private    MAX_UINT256     = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    function safeAdd (uint256 x, uint256 y) internal pure returns (uint256 z) {
        assert (x <= MAX_UINT256 - y);
        return x + y;
    }

    function safeSub (uint256 x, uint256 y) internal pure returns (uint256 z) {
        assert (x >= y);
        return x - y;
    }

    function safeMul (uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        assert(x == 0 || z / x == y);
    }
    
    function safeDiv (uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x / y;
        return z;
    }
}

contract HoneyToken is ERC20 {

    using SafeMath for uint256;
    
    address public              owner;
    address private             subowner;

    uint256 private             summarySupply;
    uint256 public              weiPerMinToken;
        
	string  public              name = "Honey Token";
	string  public              symbol = "honey";
	uint8   public              decimals = 5;
    
    bool    public              contractEnable = true;
    
    mapping(address => uint8)                        private   group;
    mapping(address => uint256)                      private   accounts;
    mapping(address => mapping (address => uint256)) private   allowed;

    event EvGroupChanged(address _address, uint8 _oldgroup, uint8 _newgroup);
    event EvTokenAdd(uint256 _value, uint256 _lastSupply);
    event EvTokenRm(uint256 _delta, uint256 _value, uint256 _lastSupply);
    event EvLoginfo(string _functionName, string _text);
    event EvMigration(address _address, uint256 _balance, uint256 _secret);
    
    struct groupPolicy {
        uint8 _default;
        uint8 _backend;
        uint8 _migration;
        uint8 _admin;
        uint8 _subowner;
        uint8 _owner;
    }
    
    groupPolicy private currentState = groupPolicy(0, 3, 9, 4, 2, 9);
    
    function HoneyToken(uint256 _weiPerMinToken, uint256 _startTokens) public {
        owner = msg.sender;
        group[msg.sender] = 9;
        
        if (_weiPerMinToken != 0)
            weiPerMinToken = _weiPerMinToken;

        accounts[owner]  = _startTokens;
        summarySupply    = _startTokens;
        
    }

    modifier minGroup(int _require) {
        require(group[msg.sender] >= _require);
        _;
    }

    modifier onlyPayloadSize(uint size) {
        assert(msg.data.length >= size + 4);
        _;
    }

    function serviceGroupChange(address _address, uint8 _group) minGroup(currentState._admin) external returns(uint8) {
        uint8 old = group[_address];
        if(old <= currentState._admin) {
            group[_address] = _group;
            EvGroupChanged(_address, old, _group);
        }
        return group[_address];
    } 
    
    function serviceGroupGet(address _check) minGroup(currentState._backend) external constant returns(uint8 _group) {
        return group[_check];
    }

    
    function settingsSetWeiPerMinToken(uint256 _weiPerMinToken) minGroup(currentState._admin) external { 
        if (_weiPerMinToken > 0) { 
            weiPerMinToken = _weiPerMinToken; 
            
            EvLoginfo("[weiPerMinToken]", "changed"); 
        }
    } 
        
    function serviceIncreaseBalance(address _who, uint256 _value) minGroup(currentState._backend) external returns(bool) {    
        accounts[_who] = accounts[_who].safeAdd(_value);
        summarySupply = summarySupply.safeAdd(_value);

        EvTokenAdd(_value, summarySupply);
        return true;
    }

    function serviceDecreaseBalance(address _who, uint256 _value) minGroup(currentState._backend) external returns(bool) {    
        accounts[_who] = accounts[_who].safeSub(_value);
        summarySupply = summarySupply.safeSub(_value);

        EvTokenRm(accounts[_who], _value, summarySupply);
        return true;
    }
    
    function serviceChangeOwner(address _newowner) minGroup(currentState._subowner) external returns(address) {
        address temp;
        uint256 value;

        if (msg.sender == owner) {
            subowner = _newowner;
            group[msg.sender] = currentState._subowner;
            group[_newowner] = currentState._subowner;
            
            EvGroupChanged(_newowner, currentState._owner, currentState._subowner);
        }

        if (msg.sender == subowner) {
            temp = owner;
            value = accounts[owner];
            
            accounts[owner] = accounts[owner].safeSub(value);
            accounts[subowner] = accounts[subowner].safeAdd(value);

            owner = subowner;
            
            delete group[temp];
            group[subowner] = currentState._owner;

            subowner = 0x00;
    
            EvGroupChanged(_newowner, currentState._subowner, currentState._owner);
        }

        return subowner;
    }

    function userTransfer(address _to, uint256 _value) onlyPayloadSize(64) minGroup(currentState._default) external returns (bool success) {
        if (accounts[msg.sender] >= _value) {
            accounts[msg.sender] = accounts[msg.sender].safeSub(_value);
            accounts[_to] = accounts[_to].safeAdd(_value);
            Transfer(msg.sender, _to, _value);
            return true;
        } else {
            return false;
        }
    }
 
    function userTransferFrom(address _from, address _to, uint256 _value) onlyPayloadSize(64) minGroup(currentState._default) external returns (bool success) { 
        if ((accounts[_from] >= _value) && (allowed[_from][msg.sender] >= _value)) {
            accounts[_from] = accounts[_from].safeSub(_value);
            allowed[_from][msg.sender] = allowed[_from][msg.sender].safeSub(_value);
            accounts[_to] = accounts[_to].safeAdd(_value);
            Transfer(_from, _to, _value);
            return true;
        } else {
            return false;
        }
    }
 
    function userApprove(address _spender, uint256 _old, uint256 _new) onlyPayloadSize(64) minGroup(currentState._default) external returns (bool success) {
       if (_old == allowed[msg.sender][_spender]) {
            allowed[msg.sender][_spender] = _new;
            Approval(msg.sender, _spender, _new);
            return true;
       } else {
            return false;
       }
    }
  
    function allowance(address _owner, address _spender) external constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function balanceOf(address _owner) external constant returns (uint256 balance) {
        if (_owner == 0x00)
            return accounts[msg.sender];
        return accounts[_owner];
    }
    
    function totalSupply() external constant returns (uint256 _totalSupply) {
        _totalSupply = summarySupply;
    }
    
    function destroy() minGroup(currentState._owner) external { 
        selfdestruct(owner); 
    }
}

contract NODE {
    
    using SafeMath for uint256;
    
    HoneyToken public  parent;
    
    mapping(address => uint256)         private   accounts;
    mapping(address => uint8)           private   group;
    uint256                             public  startTime;   
    uint256                             public  numberOfDays;
    uint8                               public  sale;
    
    struct groupPolicy {
        uint8 _backend;
        uint8 _admin;
    }
    
    groupPolicy private currentState = groupPolicy(3,4);
    
    event EvTokenBuy(address _to, uint256 _value);
    event EvGroupChanged(address _address, uint8 _oldgroup, uint8 _newgroup);
    event EvTokensStatus(address _address, uint256 _tokens);
    
    function NODE(address _conowner, uint256 _startTime, uint256 _numberOfDays, uint8 _sale) public {
        parent = HoneyToken(_conowner);
        
        require(parent.owner() == msg.sender);
        sale = _sale;
        startTime = _startTime;
        numberOfDays = _numberOfDays;
        
        group[msg.sender] = currentState._admin;
    }
    
    modifier onlyOwner(){
        require(msg.sender == parent.owner());
        _;
    }
    
    modifier minGroup(int _require) {
        require(group[msg.sender] >= _require);
        _;
    }
    
    function infoTime() public constant returns (uint256) {
        return block.timestamp;
    }
    
    function infoTokenCostValue() public view returns (uint256) {
        uint256 value = parent.weiPerMinToken();
        value = value.safeMul(100 - sale);
        value = value.safeDiv(100);
        return value;
    }
    
    function infoToday() public constant returns (uint256) {
        return infoDayFor(infoTime());
    }
    
    function infoDayFor(uint256 timestamp) public constant returns (uint256) {
        return timestamp < startTime
            ? 0
            : timestamp.safeSub(startTime) / 23 hours + 1;
    }
    
    function infoTokensLeft() external constant returns(uint256 balance) {
        return parent.balanceOf(this);
    }
    
    function serviceTokensBought(address _address) external minGroup(currentState._backend) returns(uint256 balance) {
        address info = _address;
        
        if(info == 0x00)
            info = msg.sender;
        
        EvTokensStatus(info, accounts[info]);
        
        return accounts[info]; 
    }
    
    function serviceTokensBurn(address _address) external minGroup(currentState._backend) returns(uint256 balance) {
        accounts[_address] = 0;
        return accounts[_address];
    }
    
    function serviceGetWei() external minGroup(currentState._admin) returns(bool success) {
        uint256 contractBalance = this.balance;
        
        parent.owner().transfer(contractBalance);
        
        return true;
    }
    
    function serviceGroupChange(address _address, uint8 _group) minGroup(currentState._admin) external returns(uint8) {
        uint8 old = group[_address];
        if(old <= currentState._admin) {
            group[_address] = _group;
            EvGroupChanged(_address, old, _group);
        }
        return group[_address];
    } 
    
    function serviceDestroy() external onlyOwner() {
        
        uint256 balance = parent.balanceOf(this);
        require(parent.userTransfer(parent.owner(), balance));
        
        selfdestruct(parent.owner());
    } 
    
    function buyTokens(address _who) payable external returns(uint256) {
        assert(infoTime() >= startTime && infoToday() <= numberOfDays);
        
        uint256 tokenCount;
        address who = _who;
        
        uint256 value = parent.weiPerMinToken();
        value = value.safeMul(100 - sale);
        value = value.safeDiv(100);
        
        tokenCount = msg.value.safeDiv(value);
        
        if(tokenCount != 0) {
            if (_who == 0) {
                who = msg.sender;
            }
            
            require(parent.userTransfer(who, tokenCount));
            
            if(accounts[who] != 0)
                accounts[who].safeAdd(tokenCount);
            else
                accounts[who] = tokenCount;
                
            EvTokenBuy(who, accounts[who]);
        }
        return tokenCount;
    }

    function() external payable { 
        assert(infoTime() >= startTime && infoToday() <= numberOfDays);
        
        uint256 tokenCount = msg.value.safeDiv(parent.weiPerMinToken());

        require(parent.userTransfer(msg.sender, tokenCount));
        EvTokenBuy(msg.sender, tokenCount);
    }
}