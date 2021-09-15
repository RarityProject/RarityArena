// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface Rarity {
    function summoner(uint256)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function ownerOf(uint256) external view returns (address);
}

interface ESS {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function is_registered(uint256) external view returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

interface rarity_attributes {
    function character_created(uint256) external view returns (bool);

    function ability_scores(uint256)
        external
        view
        returns (
            uint32,
            uint32,
            uint32,
            uint32,
            uint32,
            uint32
        );
}

interface codex_base_random {
    function dn(uint256 _summoner, uint256 _number)
        external
        view
        returns (uint256);
}

interface RarityFightingMap {}

contract RarityArena {
    using SafeMath for uint256;

    mapping(uint256 => mapping(address => uint256)) score;
    mapping(uint256 => mapping(uint256 => bool)) is_in_pool;
    mapping(address => uint256) daily_reward_log;
    uint256 daily_reward = 1000 * 10**18;
    uint256 reward_limit = 10**10;
    uint256 constant season_duration = 21 days;
    uint256 constant pool_capacity = 8192;
    uint256 pool_max_size = 128;
    uint256 dat_start = 0;
    address[10] public winers;
    address beneficiary;
    address[] public fighting_maps;

    Rarity rarity = Rarity(0xce761D788DF608BD21bdd59d6f4B54b2e27F25Bb);
    ESS ess = ESS(0x91c42e167959FE0Cf199090eC5a520196995a218);
    rarity_attributes attributes =
        rarity_attributes(0xB5F5AF1087A8DA62A23b08C00C6ec9af21F397a1);
    codex_base_random random =
        codex_base_random(0x7426dBE5207C2b5DaC57d8e55F0959fcD99661D4);

    struct HeroFormationPool {
        uint256 season;
        uint256 season_log;
        uint256 size;
        uint256[6][pool_capacity] formats;
    }
    HeroFormationPool hfp;

    constructor() {
        uint256[6][pool_capacity] memory _formats;
        hfp = HeroFormationPool(1, block.timestamp, 0, _formats);
        beneficiary = msg.sender;
    }

    function add_fighting_map(address _map) external {
        require(
            msg.sender == beneficiary,
            "You don't have permission to add maps"
        );
        fighting_maps.push(_map);
    }

    function map_number() external view returns (uint256) {
        return fighting_maps.length;
    }

    function add2pool(uint256[6] calldata my_format) external {
        if (block.timestamp.sub(hfp.season_log) > season_duration) {
            new_season();
        }
        if (hfp.size < pool_max_size) {
            _add_format_to_pool(my_format);
        }
    }

    function pvp_random(uint256[6] calldata my_format) external payable {
        if (block.timestamp.sub(hfp.season_log) > season_duration) {
            new_season();
        }
        uint256 opponent_index = random.dn(
            my_format[0]
                .add(my_format[1])
                .add(my_format[2])
                .add(my_format[3])
                .add(my_format[4])
                .add(my_format[5]),
            hfp.size
        );
        bool result = _fight(my_format, opponent_index);
        if (result) {
            payable(msg.sender).transfer(msg.value);
            score[hfp.season][msg.sender]++;
            if (block.timestamp > daily_reward_log[msg.sender]) {
                ess.transfer(msg.sender, daily_reward);
                daily_reward_log[msg.sender] = block.timestamp.add(1 days);
            }
        } else {
            for (uint256 i; i < 6; i++) {
                payable(rarity.ownerOf(hfp.formats[opponent_index][i]))
                    .transfer(10**17);
            }
            payable(beneficiary).transfer(10**17);
            ess.transfer(msg.sender, daily_reward.div(2));
        }
    }

    function _fight(uint256[6] calldata _me, uint256 _opponent_index)
        internal
        view
        returns (bool)
    {
        // todo add the fight code
        uint256[6] memory _opponent = hfp.formats[_opponent_index];
        return _me[0] == _opponent[0];
        // return true;
    }

    function new_season() public {
        require(block.timestamp.sub(hfp.season_log) > season_duration);
        _distribute_reward();
        _reset_hfp();
        daily_reward = daily_reward.mul(97).div(100);
        if(pool_max_size < 8000) {
            pool_max_size *= 2;
        }
    }

    function _distribute_reward() private {
        uint256 ftm_reward = address(this).balance;
        uint256 ess_reward = ess.balanceOf(address(this));
        for (uint256 i = 0; i < 10; i++) {
            ftm_reward = ftm_reward.div(2);
            if (ftm_reward > reward_limit) {
                payable(winers[i]).transfer(ftm_reward);
            }
            ess_reward = ess_reward.div(2);
            if (ess_reward > reward_limit) {
                ess.transfer(winers[i], ess_reward.div(2));
            }
        }
    }

    function _reset_hfp() private {
        hfp.season++;
        hfp.season_log = block.timestamp;
        hfp.size = 0;
    }

    function _add_format_to_pool(uint256[6] calldata _format) internal {
        require(
            hfp.size < pool_max_size,
            "The pool is full, please wait for next season"
        );
        require(_check_format(_format), "Your hero formation unqualified");
        hfp.formats[hfp.size] = _format;
        hfp.size++;
    }

    function _check_format(uint256[6] calldata _format)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < 6; i++) {
            uint256 _id = _format[i];
            if (rarity.ownerOf(_id) != msg.sender) {
                return false;
            }
            if (!attributes.character_created(_id)) {
                return false;
            }
            if (!ess.is_registered(_id)) {
                return false;
            }
            if (!is_in_pool[hfp.season][_id]) {
                return false;
            }
        }
        return true;
    }
}
