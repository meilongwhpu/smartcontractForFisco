pragma solidity ^0.4.25;

struct imap {
    mapping(uint256 => uint256) map;
    uint256 head;
    uint256 tail;
}

library Queue {
    function enqueue(imap storage im, uint256 b) internal {
        assert(im.head <= im.tail);
        im.map[im.tail] = b;
        im.tail++;
    }

    function dequeue(imap storage im) internal returns(uint256 r) {
        assert(im.head < im.tail);
        r = im.map[im.head];
        delete im.map[im.head];
        im.head++;
        return r;
    }

    function front(imap storage im) internal view returns(uint256) {
        assert(im.head < im.tail);
        return im.map[im.head];
    }

    function len(imap storage im) internal view returns(uint256) {
        assert(im.head <= im.tail);
        return im.tail - im.head;
    }
}
