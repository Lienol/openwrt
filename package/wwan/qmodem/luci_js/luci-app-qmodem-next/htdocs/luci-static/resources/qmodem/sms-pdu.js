var pduParser = {};

pduParser.parse = function(pdu) {
    //Cursor points to the last octet we've read.
    var cursor = 0;

    var buffer = new Buffer(pdu.slice(0,4), 'hex');
    var smscSize = buffer[0];
    var smscType = buffer[1].toString(16);
    cursor = (smscSize*2+2);
    var smscNum  = pduParser.deSwapNibbles(pdu.slice(4, cursor));

    var buffer = new Buffer(pdu.slice(cursor,cursor+6), 'hex');
    cursor += 6;
    var smsDeliver = buffer[0];

    var smsDeliverBits = ("00000000"+parseInt(smsDeliver).toString(2)).slice(-8);
    var udhi = smsDeliverBits.slice(1,2) === "1";

    var senderSize = buffer[1];
    if(senderSize % 2 === 1)
        senderSize++;

    var senderType = parseInt(buffer[2]).toString(16)

    var encodedSender = pdu.slice(cursor, cursor + senderSize);
    var senderNum;
    if (senderType === '91') {
        senderNum = pduParser.deSwapNibbles(encodedSender);
    } else if (senderType === 'd0') {
        senderNum = this.decode7Bit(encodedSender).replace(/\0/g, '');
    } else {
        console.error('unsupported sender type.');
    }

    cursor += senderSize;

    var protocolIdentifier = pdu.slice(cursor, cursor+2);
    cursor += 2;

    var dataCodingScheme = pdu.slice(cursor, cursor+2);
    cursor = cursor+2;

    var encoding = pduParser.detectEncoding(dataCodingScheme);

    var timestamp = pduParser.deSwapNibbles(pdu.slice(cursor, cursor+14));


    var time = new Date;
    time.setUTCFullYear('20'+timestamp.slice(0,2));
    time.setUTCMonth(timestamp.slice(2,4)-1);
    time.setUTCDate(timestamp.slice(4,6));
    time.setUTCHours(timestamp.slice(6,8));
    time.setUTCMinutes(timestamp.slice(8,10));
    time.setUTCSeconds(timestamp.slice(10,12));

    var firstTimezoneOctet = parseInt(timestamp.slice(12,13));
    var binary = ("0000"+firstTimezoneOctet.toString(2)).slice(-4);
    var factor = binary.slice(0,1) === '1' ? 1 : -1;
    var binary = '0'+binary.slice(1, 4);
    var firstTimezoneOctet = parseInt(binary, 2).toString(10);
    var timezoneDiff = parseInt(firstTimezoneOctet + timestamp.slice(13, 14));
    var time = new Date(time.getTime() + (timezoneDiff * 15 * 1000 * 60 * factor));

    cursor += 14;

    var dataLength = parseInt(pdu.slice(cursor, cursor+2), 16).toString(10);
    cursor += 2;

    if(udhi) { //User-Data-Header-Indicator: means there's some User-Data-Header.
        var udhLength = pdu.slice(cursor, cursor+2);
        var iei = pdu.slice(cursor+2, cursor+4);
        if(iei == "00") { //Concatenated sms.
            var headerLength = pdu.slice(cursor+4, cursor+6);
            var referenceNumber = pdu.slice(cursor+6, cursor+8);
            var parts = pdu.slice(cursor+8, cursor+10);
            var currentPart = pdu.slice(cursor+10, cursor+12);
        }

        if(iei == "08") { //Concatenaded sms with a two-bytes reference number
            var headerLength = pdu.slice(cursor+4, cursor+6);
            var referenceNumber = pdu.slice(cursor+6, cursor+10);
            var parts = pdu.slice(cursor+10, cursor+12);
            var currentPart = pdu.slice(cursor+12, cursor+14);
        }

        if(encoding === '16bit')
            if(iei == '00')
                cursor += (udhLength-2)*4;
            else if(iei == '08')
                cursor += ((udhLength-2)*4)+2;
        else
            cursor += (udhLength-2)*2;
    }

    if(encoding === '16bit')
        var text = pduParser.decode16Bit(pdu.slice(cursor), dataLength);
    else if(encoding === '7bit')
        var text = pduParser.decode7Bit(pdu.slice(cursor), dataLength);
    else if(encoding === '8bit')
        var text = ''; //TODO

    var data = {
        'smsc' : smscNum,
        'smsc_type' : smscType,
        'sender' : senderNum,
        'sender_type' : senderType,
        'encoding' : encoding,
        'time' : time,
        'text' : text
    };

    if(udhi) {
        data['udh'] = {
            'length' : udhLength,
            'iei' : iei,
        };

        if(iei == '00' || iei == '08') {
            data['udh']['reference_number'] = referenceNumber;
            data['udh']['parts'] = parseInt(parts);
            data['udh']['current_part'] = parseInt(currentPart);
        }
    }

    return data;
}

pduParser.detectEncoding = function(dataCodingScheme) {
    var binary = ('00000000'+(parseInt(dataCodingScheme, 16).toString(2))).slice(-8);

    if(binary == '00000000')
        return '7bit';

    if(binary.slice(0, 2) === '00') {
        var compressed = binary.slice(2, 1) === '1';
        var bitsHaveMeaning = binary.slice(3, 1) === '1';

        if(binary.slice(4,6) === '00')
            return '7bit';

        if(binary.slice(4,6) === '01')
            return '8bit';

        if(binary.slice(4,6) === '10')
            return '16bit';
    }
}

pduParser.decode16Bit = function(data, length) {
    //We are getting ucs2 characters.
    var ucs2 = '';
    for(var i = 0;i<=data.length;i=i+4) {
        ucs2 += String.fromCharCode("0x"+data[i]+data[i+1]+data[i+2]+data[i+3]);
    }

    return ucs2;
}

pduParser.deSwapNibbles = function(nibbles) {
    var out = '';
    for(var i = 0; i< nibbles.length; i=i+2) {
        if(nibbles[i] === 'F') //Dont consider trailing F.
            out += parseInt(nibbles[i+1], 16).toString(10);
        else
            out += parseInt(nibbles[i+1], 16).toString(10)+parseInt(nibbles[i], 16).toString(10);
    }
    return out;
}

pduParser.decode7Bit = function(code, count) {
    //We are getting 'septeps'. We should decode them.
    var binary = '';
    for(var i = 0; i<code.length;i++)
        binary += ('0000'+parseInt(code.slice(i,i+1), 16).toString(2)).slice(-4);

    var bin = Array();
    var cursor = 0;
    var fromPrevious = '';
    var i = 0;
    while(binary[i]) {
        var remaining = 7 - fromPrevious.length;
        var toNext = 8 - remaining;
        bin[i] = binary.slice(cursor+toNext, cursor+toNext+remaining) + fromPrevious;
        var fromPrevious = binary.slice(cursor, cursor+toNext);
        if(toNext === 8)
            fromPrevious = '';
        else
            cursor += 8;
        i++;
    }

    var ascii = '';
    for(i in bin)
        ascii += String.fromCharCode(parseInt(bin[i], 2));

    return ascii;
}

pduParser.encode7Bit = function(ascii) {
    //We should create septeps now.
    var octets = new Array();
    for(var i = 0; i<ascii.length; i++)
        octets.push(('0000000'+(ascii.charCodeAt(i).toString(2))).slice(-7));

    for(var i in octets) {
        var i = parseInt(i);
        var freeSpace = 8 - octets[i].length;

        if(octets[i+1] && freeSpace !== 8) {
            octets[i] = octets[i+1].slice(7-freeSpace) + octets[i];
            octets[i+1] = octets[i+1].slice(0, 7-freeSpace);
        }
    }

    var hex = '';
    for(i in octets)
        if(octets[i].length > 0)
            hex += ('00'+(parseInt(octets[i], 2).toString(16))).slice(-2);
    return hex;
}

//TODO: TP-Validity-Period (Delivery)
pduParser.generate = function(message) {
    var pdu = '00';

    var parts = 1;
    if(message.encoding === '16bit' && message.text.length > 70)
        parts = message.text.length / 66;

    else if(message.encoding === '7bit' && message.text.length > 160)
        parts = message.text.length / 153;

    parts = Math.ceil(parts);

    var TPMTI  = 1;
    var TPRD   = 4;
    var TPVPF  = 8;
    var TPSRR  = 32;
    var TPUDHI = 64;
    var TPRP   = 128;

    var submit = TPMTI;

    if(parts > 1) //UDHI
        submit = submit | TPUDHI;

    submit = submit | TPSRR;

    pdu += submit.toString(16);

    pdu += '00'; //TODO: Reference Number;

    var receiverSize = ('00'+(parseInt(message.receiver.length, 10).toString(16))).slice(-2);
    var receiver = pduParser.swapNibbles(message.receiver);
    var receiverType = 81; //TODO: NOT-Hardcoded PDU generation. Please note that Hamrah1 doesnt work if we set it to 91 (International).

    pdu += receiverSize.toString(16) + receiverType + receiver;

    pdu += '00'; //TODO TP-PID

    if(message.encoding === '16bit')
        pdu += '08';
    else if(message.encoding === '7bit')
        pdu += '00';

    var pdus = new Array();

    var csms = randomHexa(2); // CSMS allows to give a reference to a concatenated message

    for(var i=0; i< parts; i++) {
        pdus[i] = pdu;

        if(message.encoding === '16bit') {
            /* If there are more than one messages to be sent, we are going to have to put some UDH. Then, we would have space only
             * for 66 UCS2 characters instead of 70 */
            if(parts === 1)
                var length = 70;
            else
                var length = 66;

        } else if(message.encoding === '7bit') {
            /* If there are more than one messages to be sent, we are going to have to put some UDH. Then, we would have space only
             * for 153 ASCII characters instead of 160 */
            if(parts === 1)
                var length = 160;
            else
                var length = 153;
        }
        var text = message.text.slice(i*length, (i*length)+length);

        var user_data;
        var size;
        if(message.encoding === '16bit') {
            user_data = pduParser.encode16Bit(text);
            size = (user_data.length / 2);

            if(parts > 1)
                size += 6; //6 is the number of data headers we append.

        } else if(message.encoding === '7bit') {
            user_data = pduParser.encode7Bit(text);
            size = user_data.length / 2;
        }

        pdus[i] += ('00'+parseInt(size).toString(16)).slice(-2);

        if(parts > 1) {
            pdus[i] += '05';
            pdus[i] += '00';
            pdus[i] += '03';
            pdus[i] +=  csms;
            pdus[i] += ('00'+parts.toString(16)).slice(-2);
            pdus[i] += ('00'+(i+1).toString(16)).slice(-2);
        }
        pdus[i] += user_data;
    }

    return pdus;
}


pduParser.encode16Bit = function(text) {
    var out = '';
    for(var i = 0; i<text.length;i++) {
        out += ('0000'+(parseInt(text.charCodeAt(i), 10).toString(16))).slice(-4);
    }
    return out;
}

pduParser.swapNibbles = function(nibbles) {
    var out = '';
    for(var i = 0; i< nibbles.length; i=i+2) {
        if(typeof(nibbles[i+1]) === 'undefined') // Add a trailing F.
            out += 'F'+parseInt(nibbles[i], 16).toString(10);
        else
            out += parseInt(nibbles[i+1], 16).toString(10)+parseInt(nibbles[i], 16).toString(10);
    }
    return out;
}

pduParser.parseStatusReport = function(pdu) {
    //Cursor points to the last octet we've read.
    var cursor = 0;

    var smscSize = parseInt(pdu.slice(0, 2), 16);
    cursor += 2;

    var smscType = parseInt(pdu.slice(cursor, cursor+2), 16);
    cursor += 2;

    var smscNum  = pduParser.deSwapNibbles(pdu.slice(cursor, (smscSize*2)+2));
    cursor = (smscSize*2+2);

    var header = parseInt(pdu.slice(cursor,cursor+2));
    cursor += 2;

    var reference = parseInt(pdu.slice(cursor,cursor+2), 16);
    cursor += 2;

    var senderSize = parseInt(pdu.slice(cursor,cursor+2), 16);
    if(senderSize % 2 === 1)
        senderSize++;
    cursor += 2;

    var senderType = parseInt(pdu.slice(cursor,cursor+2));
    cursor += 2;

    var sender = pduParser.deSwapNibbles(pdu.slice(cursor, cursor+senderSize));

    var status = pdu.slice(-2);

    return {
        smsc:smscNum,
        reference:reference,
        sender:sender,
        status:status
    }
}

function randomHexa(size)
{
    var text = "";
    var possible = "0123456789ABCDEF";
    for( var i=0; i < size; i++ )
        text += possible.charAt(Math.floor(Math.random() * possible.length));
    return text;
}


class LuciTable{
        constructor(){
            this.rows = [];
            this.tbody;
            this.fieldset;
            this.init_table();
        }

        init_table(){
            //create a luci fieldset (class cbi-section)
            var fieldset = document.createElement('fieldset');
            fieldset.className="cbi-section";
            //set fieldset Header name
            var legend = document.createElement('legend');
            var title_span = document.createElement('span');
            title_span.className="panel-title"
            //init table
            var table = document.createElement('table');
            var tbody = document.createElement('tbody');
            table.className="table"
            //save
            this.fieldset = fieldset;
            this.tbody = tbody
            this.title_span = title_span
            this.legend = legend
            
            fieldset.appendChild(legend);
            fieldset.appendChild(title_span);
            table.appendChild(tbody)
            fieldset.appendChild(table)
        }

        new_tr(data,index){
            var type = data.type;
            var col = data.col;
            var left = data.left;
            var right = data.right;
            //clear the row
            this.rows[index].left.innerHTML = "";
            this.rows[index].right.innerHTML = "";
            //set the row
            this.rows[index].left.appendChild(left);
            this.rows[index].right.appendChild(right);
            if (right == null || right == "") {
                this.rows[index].row.style.display = "none";
            }
            else{
                this.rows[index].row.style.display = "";
            }
        }


        set title(value){
            this.legend.innerHTML = value;
            this.title_span.innerHTML = value;
        }

        set object_data(value){
            var row_length = this.rows.length;
            var value_length = Object.keys(value).length;
            if (row_length < value_length) {
                for ( let i = row_length; i < value_length; i++) {
                    let row = document.createElement('tr');
                    row.className = "tr"
                    let cell_left = document.createElement('td');
                    cell_left.classList.add("td")
                    cell_left.setAttribute("width","33%")
                    let cell_right = document.createElement('td');
                    cell_right.classList.add("td");
                    row.appendChild(cell_left);
                    row.appendChild(cell_right);
                    this.tbody.appendChild(row);
                    var row_dict = {
                        "row":row,
                        "left":cell_left,
                        "right":cell_right,
                    }
                    this.rows.push(row_dict);
                }
            }
            else if(row_length > value_length){
                for (let i = value_length; i < row_length; i++) {
                    this.tbody.removeChild(this.rows[i].row);
                }
                this.rows = this.rows.slice(0,value_length);
            }
            var index = 0;
            for (var key in value) {
                this.rows[index].left.innerHTML = key;
                this.rows[index].right.innerHTML = value[key];
                index++;
            }
        }
        
        set array_data(value){
            var row_length = this.rows.length;
            var value_length = value.length;
            if (row_length < value_length) {
                for ( let i = row_length; i < value_length; i++) {
                    let row = document.createElement('tr');
                    row.className = "tr"
                    let cell_left = document.createElement('td');
                    cell_left.classList.add("td")
                    cell_left.setAttribute("width","33%")
                    let cell_right = document.createElement('td');
                    cell_right.classList.add("sms_recv_content")
                    cell_right.classList.add("td")
                    row.appendChild(cell_left);
                    row.appendChild(cell_right);
                    this.tbody.appendChild(row);
                    var row_dict = {
                        "row":row,
                        "left":cell_left,
                        "right":cell_right,
                    }
                    this.rows.push(row_dict);
                }
            }
            else if(row_length > value_length){
                for (let i = value_length; i < row_length; i++) {
                    this.tbody.removeChild(this.rows[i].row);
                }
                this.rows = this.rows.slice(0,value_length);
            }
            for (let i = 0; i < value.length; i++) {
                this.new_tr(value[i],i);
            }
        }

        set data(value){
            if (value == null) {
                return;
            }
            if (Array.isArray(value)) {
                this.array_data = value;
            }
            else{
                this.object_data = value;
            }
        }
    }

// Export pduParser as a proper module
return L.Class.extend({
    parse: pduParser.parse.bind(pduParser),
    detectEncoding: pduParser.detectEncoding.bind(pduParser),
    decode16Bit: pduParser.decode16Bit.bind(pduParser),
    deSwapNibbles: pduParser.deSwapNibbles.bind(pduParser),
    decode7Bit: pduParser.decode7Bit.bind(pduParser),
    encode7Bit: pduParser.encode7Bit.bind(pduParser),
    generate: pduParser.generate.bind(pduParser),
    encode16Bit: pduParser.encode16Bit.bind(pduParser),
    swapNibbles: pduParser.swapNibbles.bind(pduParser),
    parseStatusReport: pduParser.parseStatusReport.bind(pduParser)
});
