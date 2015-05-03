// storage form in progress curves

var h = new Array;

function get(id) {
    for (var i = 0; i < h.length; i++) {	
	if (h[i].id === id) { return h[i]; }
    }
    return null;
}

function set(id, value) {
    value.id = id;
    for (var i = 0; i < h.length; i++) {
	if (h[i].id === id) { h[i] = value; return; }
    }
    h.push(value);
}

function remove(id) {
    for (var i = 0; i < h.length; i++) {
        if (h[i].id === id) {
            h.splice(i, 1);
            break;
        }
    }
}

