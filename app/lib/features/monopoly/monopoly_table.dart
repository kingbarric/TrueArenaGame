import 'package:flutter/material.dart';
import 'monopoly_board.dart';

typedef MonopolyAction = void Function(
    String action, Map<String, dynamic> data);

/// Presentation is independent of the socket, making the actual phone layout
/// reviewable with the same authoritative snapshot used in a live match.
class MonopolyTable extends StatefulWidget {
  const MonopolyTable(
      {super.key,
      required this.state,
      required this.selfId,
      required this.names,
      required this.onAction,
      required this.onProperties,
      required this.onTrade,
      required this.chatController,
      required this.messages,
      required this.onSendChat,
      required this.onBack,
      this.huudName = 'Your Huud',
      this.voice,
      this.connected = true,
      this.pending = false,
      this.spectating = false,
      this.canChat = true,
      this.seconds = 180,
      this.error,
      this.watching = 0,
      this.speaking = const {}});
  final Map<String, dynamic> state;
  final String selfId, huudName;
  final Map<String, String> names;
  final MonopolyAction onAction;
  final VoidCallback onProperties, onTrade, onSendChat, onBack;
  final TextEditingController chatController;
  final List<({String who, String text})> messages;
  final Widget? voice;
  final Set<String> speaking;
  final bool connected, pending, spectating, canChat;
  final int seconds, watching;
  final String? error;
  @override
  State<MonopolyTable> createState() => _MonopolyTableState();
}

class _MonopolyTableState extends State<MonopolyTable> {
  int? _selected;
  String name(String? id) => widget.names[id] ?? 'Player';
  bool get _enabled =>
      widget.connected &&
      !widget.pending &&
      !widget.spectating &&
      monopolyPlayers(widget.state).contains(widget.selfId);
  bool get _myDecision =>
      _enabled && widget.state['decisionPlayer'] == widget.selfId;
  String get _phase => widget.state['phase']?.toString() ?? '';
  Widget button(String label, VoidCallback? tap,
          {Color color = monopolyWine, IconData? icon}) =>
      FilledButton(
          onPressed: tap,
          style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor:
                  color == monopolyGold ? monopolyInk : monopolyCream,
              disabledBackgroundColor: const Color(0xff907b66),
              disabledForegroundColor: const Color(0xffddd0bb),
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'MonopolySans')),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 6)
            ],
            Flexible(
                child: Text(label, maxLines: 2, textAlign: TextAlign.center))
          ]));
  @override
  Widget build(BuildContext context) {
    final state = widget.state,
        players = monopolyPlayers(state),
        people = monopolyMap(state['playerState']);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final chipWidth =
        ((MediaQuery.sizeOf(context).width - 20 - 18) / 4).clamp(88.0, 130.0) *
            textScale;
    final boardSize = (MediaQuery.sizeOf(context).height * .38)
        .clamp(260.0, MediaQuery.sizeOf(context).width - 20);
    final me = monopolyMap(people[widget.selfId]);
    final winner = state['winner']?.toString();
    return Theme(
        data: Theme.of(context).copyWith(
            textTheme:
                Theme.of(context).textTheme.apply(fontFamily: 'MonopolySans')),
        child: DecoratedBox(
          decoration: const BoxDecoration(
              image: DecorationImage(
                  image: AssetImage('assets/images/monopoly/walnut.png'),
                  fit: BoxFit.cover),
              color: Color(0xff3f271e)),
          child: Column(children: [
            Container(
                color: const Color(0xdd211613),
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                child: Row(children: [
                  IconButton(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: monopolyCream),
                      tooltip: 'Back to Huud'),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(widget.huudName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: monopolyCream,
                                fontWeight: FontWeight.w900,
                                fontSize: 18)),
                        Text('MONOPOLY  •  ${widget.watching} watching',
                            style: const TextStyle(
                                color: monopolyGold,
                                fontWeight: FontWeight.w800,
                                fontSize: 11))
                      ])),
                  if (widget.voice != null) widget.voice!,
                  if (widget.pending)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: monopolyGold)),
                ])),
            Expanded(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(children: [
                      SizedBox(
                          height: 62 * textScale,
                          child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: players.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (_, seat) {
                                final id = players[seat],
                                    p = monopolyMap(people[id]),
                                    active = id == state['decisionPlayer'];
                                return Container(
                                    width: chipWidth,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 5),
                                    decoration: BoxDecoration(
                                        color: active
                                            ? monopolyWine
                                            : const Color(0xee2b2019),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: widget.speaking.contains(id)
                                                ? const Color(0xff7fdda8)
                                                : active
                                                    ? monopolyGold
                                                    : const Color(0xff826341),
                                            width: active ? 2 : 1),
                                        boxShadow: const [
                                          BoxShadow(
                                              color: Color(0x60000000),
                                              offset: Offset(0, 3),
                                              blurRadius: 2)
                                        ]),
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Row(children: [
                                            MonopolyToken(seat: seat, size: 23),
                                            if (widget.speaking.contains(id))
                                              const Icon(Icons.mic_rounded,
                                                  size: 11,
                                                  color: Color(0xff7fdda8)),
                                            const SizedBox(width: 3),
                                            Expanded(
                                                child: Text(
                                                    id == widget.selfId
                                                        ? 'You'
                                                        : name(id),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        color: monopolyCream,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 12)))
                                          ]),
                                          Text(
                                              p['bankrupt'] == true
                                                  ? 'OUT'
                                                  : '\$${p['cash'] ?? 1500}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: p['bankrupt'] == true
                                                      ? Colors.white54
                                                      : monopolyGold,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 16)),
                                          if (p['jailed'] == true)
                                            const Text('IN JAIL',
                                                maxLines: 1,
                                                style: TextStyle(
                                                    color: monopolyCream,
                                                    fontSize: 8,
                                                    fontWeight:
                                                        FontWeight.w800)),
                                        ]));
                              })),
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                                    winner != null
                                        ? '${name(winner)} wins!'
                                        : _myDecision
                                            ? 'YOUR ${_phase == 'Auction' ? 'BID' : 'TURN'}'
                                            : '${name(state['decisionPlayer']?.toString())}\'s ${_phase == 'Auction' ? 'bid' : 'turn'}',
                                    style: const TextStyle(
                                        color: monopolyCream,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900))),
                            Text(
                                widget.connected
                                    ? '${widget.seconds}s'
                                    : 'OFFLINE • saved board',
                                style: TextStyle(
                                    color: widget.connected
                                        ? monopolyGold
                                        : monopolyCream,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800)),
                          ])),
                      if (state['board'] is List)
                        Center(
                            child: SizedBox(
                                width: boardSize,
                                child: Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, 0.00065)
                                      ..rotateX(-0.18),
                                    child: MonopolyBoard(
                                        state: state,
                                        selected: _selected,
                                        onSpace: (id) => _inspectSpace(id)))))
                      else
                        const SizedBox(
                            height: 260,
                            child: Center(
                                child: Text('Opening your board…',
                                    style: TextStyle(
                                        color: monopolyCream,
                                        fontWeight: FontWeight.w800)))),
                      const SizedBox(height: 12),
                      if (widget.error != null)
                        Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: const Color(0xff5e1f2c),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(widget.error!,
                                style: const TextStyle(
                                    color: monopolyCream,
                                    fontWeight: FontWeight.w700))),
                      _decision(state, me, winner),
                      for (final raw in state['tradeOffers'] as List? ?? [])
                        _offer(monopolyMap(raw)),
                      const SizedBox(height: 9),
                      Row(children: [
                        Expanded(
                            child: button('Properties', widget.onProperties,
                                color: monopolyGold,
                                icon: Icons.domain_rounded)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: button(
                                'Trade',
                                _enabled &&
                                        const {'Roll', 'Manage', 'Debt'}
                                            .contains(_phase) &&
                                        me['bankrupt'] != true
                                    ? widget.onTrade
                                    : null,
                                color: const Color(0xff305c4c),
                                icon: Icons.swap_horiz_rounded)),
                      ]),
                      const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                              'Pinch to zoom • tap any space to inspect',
                              style: TextStyle(
                                  color: monopolyCream,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600))),
                    ]))),
            _chat(),
          ]),
        ));
  }

  void _inspectSpace(int id) {
    setState(() => _selected = id);
    final board = widget.state['board'] as List? ?? [];
    if (id >= board.length) return;
    final tile = monopolyMap(board[id]);
    final deed = monopolyMap(monopolyMap(widget.state['deeds'])['$id']);
    final rents = tile['rents'] as List? ?? [];
    final details = switch (tile['kind']) {
      'go' => 'Collect \$200 when you pass or land here.',
      'jail' =>
        'Just visiting unless you were sent to jail. Leave by paying \$50, using a jail card or rolling doubles.',
      'parking' => 'A resting space. No reward or fee.',
      'goToJail' => 'Go directly to jail. Do not collect a GO salary.',
      'tax' => 'Pay the bank \$${id == 4 ? 200 : 100}.',
      'chance' => 'Draw the next Chance card. Only the drawn card is revealed.',
      'chest' =>
        'Draw the next Community Chest card. Only the drawn card is revealed.',
      'railroad' => 'Rent: 1 railroad \$25 • 2 \$50 • 3 \$100 • 4 \$200.',
      'utility' => 'Rent: one utility 4× dice; both utilities 10× dice.',
      _ => rents.length == 6
          ? 'Rent \$${rents[0]}\n1 house \$${rents[1]} • 2 houses \$${rents[2]}\n3 houses \$${rents[3]} • 4 houses \$${rents[4]}\nHotel \$${rents[5]}\nBuilding cost \$${tile['buildingCost']} each.'
          : '',
    };
    showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
              backgroundColor: monopolyCream,
              title: Container(
                  padding: const EdgeInsets.all(12),
                  color: monopolyGroupColor(tile['group']?.toString()),
                  child: Text(tile['name'].toString().toUpperCase(),
                      style: const TextStyle(
                          color: monopolyInk,
                          fontFamily: 'MonopolySans',
                          fontWeight: FontWeight.w900,
                          fontSize: 20))),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((tile['price'] as num? ?? 0) > 0) ...[
                      Text(
                          'PRICE \$${tile['price']} • ${deed['owner'] == null ? 'BANK' : name(deed['owner']?.toString())}',
                          style: const TextStyle(
                              color: monopolyInk, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12)
                    ],
                    Text(details,
                        style: const TextStyle(
                            color: monopolyInk,
                            fontFamily: 'MonopolySans',
                            fontWeight: FontWeight.w700,
                            height: 1.5)),
                    if (deed['mortgaged'] == true)
                      const Text('MORTGAGED — no rent',
                          style: TextStyle(
                              color: monopolyWine,
                              fontWeight: FontWeight.w900)),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Close',
                        style: TextStyle(
                            color: monopolyWine, fontWeight: FontWeight.w900)))
              ],
            ));
  }

  Widget _decision(
      Map<String, dynamic> state, Map<String, dynamic> me, String? winner) {
    final board = state['board'] as List? ?? [],
        auction = monopolyMap(state['auction']);
    final current =
        (monopolyMap(monopolyMap(state['playerState'])[state['turnPlayer']])[
                    'position'] as num?)
                ?.toInt() ??
            0;
    final selected = _phase == 'Purchase'
        ? current
        : _phase == 'Auction'
            ? (auction['property'] as num?)?.toInt() ?? current
            : _selected ?? current;
    final tile = selected < board.length
        ? monopolyMap(board[selected])
        : <String, dynamic>{};
    final deed = monopolyMap(monopolyMap(state['deeds'])['$selected']);
    final price = (tile['price'] as num?)?.toInt() ?? 0;
    final title = winner != null
        ? 'MATCH COMPLETE'
        : _phase == 'Debt'
            ? 'PAYMENT DUE'
            : _phase == 'Auction'
                ? '${tile['name'] ?? 'Property'} — AUCTION'
                : tile['name']?.toString() ?? 'MONOPOLY';
    return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: monopolyCream,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xff6d4a2c), width: 2),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x90000000), offset: Offset(0, 4), blurRadius: 3)
            ]),
        child: Column(children: [
          Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: monopolyGroupColor(tile['group']?.toString()),
              child: Text(title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: monopolyInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w900))),
          Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                if (state['drawnCard'] != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(state['drawnCard'].toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: monopolyWine,
                              fontFamily: 'MonopolySans',
                              fontWeight: FontWeight.w800,
                              fontSize: 13))),
                if (state['lastPayment'] is Map)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                          '${name(monopolyMap(state['lastPayment'])['debtor']?.toString())} paid \$${monopolyMap(state['lastPayment'])['amount']} to ${monopolyMap(state['lastPayment'])['creditor'] == null ? 'the bank' : name(monopolyMap(state['lastPayment'])['creditor']?.toString())}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: monopolyInk,
                              fontWeight: FontWeight.w800,
                              fontSize: 13))),
                if (winner != null) ...[
                  Text('${name(winner)} is the last player standing',
                      style: const TextStyle(
                          color: monopolyInk, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  button('Return to Huud', widget.onBack)
                ] else if (_phase == 'Purchase') ...[
                  Text(
                      'PRICE  \$$price     •     RENT  \$${(tile['rents'] as List? ?? [
                            0
                          ]).firstOrNull ?? 0}',
                      style: const TextStyle(
                          color: monopolyInk,
                          fontWeight: FontWeight.w900,
                          fontSize: 15)),
                  const SizedBox(height: 9),
                  Row(children: [
                    Expanded(
                        child: button(
                            'Buy \$$price',
                            _myDecision &&
                                    ((me['cash'] as num?)?.toInt() ?? 0) >=
                                        price
                                ? () => widget.onAction('BUY', {})
                                : null)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: button(
                            'Auction',
                            _myDecision
                                ? () => widget.onAction('AUCTION', {})
                                : null,
                            color: const Color(0xff305c4c)))
                  ])
                ] else if (_phase == 'Auction') ...[
                  Text(
                      'HIGHEST BID  \$${auction['bid'] ?? 0}${auction['bidder'] == null ? '' : '  •  ${name(auction['bidder']?.toString())}'}',
                      style: const TextStyle(
                          color: monopolyInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 9),
                  Row(children: [
                    Expanded(
                        child: button(
                            'Place bid',
                            _myDecision
                                ? () => _bid(
                                    (auction['bid'] as num?)?.toInt() ?? 0,
                                    (me['cash'] as num?)?.toInt() ?? 0)
                                : null)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: button(
                            'Pass',
                            _myDecision
                                ? () => widget.onAction('PASS', {})
                                : null,
                            color: const Color(0xff305c4c)))
                  ])
                ] else if (_phase == 'Debt') ...[
                  Text(state['message']?.toString() ?? 'Payment due',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: monopolyInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: button(
                            'Pay now',
                            _myDecision
                                ? () => widget.onAction('PAY_DEBT', {})
                                : null)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: button('Raise cash',
                            _myDecision ? widget.onProperties : null,
                            color: const Color(0xff305c4c)))
                  ])
                ] else ...[
                  if (price > 0)
                    Text(
                        'PRICE \$$price${deed['owner'] == null ? '  •  BANK' : '  •  ${name(deed['owner']?.toString())}'}${deed['mortgaged'] == true ? ' • MORTGAGED' : ''}',
                        style: const TextStyle(
                            color: monopolyInk,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  Text(state['message']?.toString() ?? 'Roll the dice',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: monopolyInk,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(height: 8),
                  if (_phase == 'Roll')
                    button(me['jailed'] == true ? 'Try jail roll' : 'Roll dice',
                        _myDecision ? () => widget.onAction('ROLL', {}) : null,
                        icon: Icons.casino_rounded),
                  if (_phase == 'Manage')
                    button(
                        state['rollAgain'] == true ? 'Roll again' : 'End turn',
                        _myDecision
                            ? () => widget.onAction('END_TURN', {})
                            : null,
                        icon: Icons.arrow_forward_rounded),
                  if (_phase == 'Roll' && me['jailed'] == true)
                    Wrap(spacing: 8, children: [
                      TextButton(
                          onPressed: _myDecision &&
                                  ((me['cash'] as num?)?.toInt() ?? 0) >= 50
                              ? () => widget.onAction('PAY_JAIL', {})
                              : null,
                          child: const Text('Pay \$50',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: monopolyWine))),
                      if ((me['jailCards'] as List? ?? []).isNotEmpty)
                        TextButton(
                            onPressed: _myDecision
                                ? () => widget.onAction('USE_JAIL_CARD', {})
                                : null,
                            child: const Text('Use jail card',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: monopolyWine)))
                    ])
                ],
              ])),
        ]));
  }

  Widget _offer(Map<String, dynamic> offer) {
    final incoming = offer['to'] == widget.selfId;
    String deeds(String key) => (offer[key] as List? ?? []).map((id) {
          final board = widget.state['board'] as List? ?? [];
          return (id is num && id.toInt() < board.length)
              ? monopolyMap(board[id.toInt()])['name']
              : 'Deed';
        }).join(', ');
    return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: monopolyCream,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: monopolyGold, width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              incoming
                  ? 'TRADE FROM ${name(offer['from']?.toString()).toUpperCase()}'
                  : 'OFFER TO ${name(offer['to']?.toString()).toUpperCase()}',
              style: const TextStyle(
                  color: monopolyInk, fontWeight: FontWeight.w900)),
          Text(
              'They give: \$${incoming ? offer['giveCash'] : offer['takeCash']} ${deeds(incoming ? 'giveDeeds' : 'takeDeeds')}\nYou give: \$${incoming ? offer['takeCash'] : offer['giveCash']} ${deeds(incoming ? 'takeDeeds' : 'giveDeeds')}',
              style: const TextStyle(
                  color: monopolyInk, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (incoming)
              button(
                  'Accept',
                  _enabled
                      ? () => widget
                          .onAction('ACCEPT_TRADE', {'tradeId': offer['id']})
                      : null),
            button(
                incoming ? 'Decline' : 'Cancel',
                _enabled
                    ? () => widget.onAction(
                        incoming ? 'DECLINE_TRADE' : 'CANCEL_TRADE',
                        {'tradeId': offer['id']})
                    : null,
                color: const Color(0xff305c4c))
          ]),
        ]));
  }

  Future<void> _bid(int current, int cash) async {
    final input = TextEditingController(text: '${current + 10}');
    final amount = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Place your bid'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Current bid: \$$current • Your cash: \$$cash'),
                  TextField(
                      controller: input,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(
                          labelText: 'Whole amount', prefixText: '\$'))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        final v = int.tryParse(input.text);
                        if (v != null && v > current && v <= cash) {
                          Navigator.pop(context, v);
                        }
                      },
                      child: const Text('Bid'))
                ]));
    // Dialog's closing transition still references the controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    input.dispose();
    if (amount != null && mounted && _myDecision) {
      widget.onAction('BID', {'amount': amount});
    }
  }

  Widget _chat() => Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: const BoxDecoration(
          color: Color(0xff221815),
          border: Border(top: BorderSide(color: monopolyGold, width: 1.4))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.chat_bubble_rounded, size: 15, color: monopolyGold),
          const SizedBox(width: 6),
          const Text('HUUD CHAT',
              style: TextStyle(
                  color: monopolyGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 11)),
          const Spacer(),
          TextButton(
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: const Color(0xff221815),
                  builder: (_) => SafeArea(
                          child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                            const Text('HUUD CHAT',
                                style: TextStyle(
                                    color: monopolyGold,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 12),
                            for (final line in widget.messages)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text('${line.who}: ${line.text}',
                                      style: const TextStyle(
                                          color: monopolyCream, fontSize: 15)))
                          ]))),
              child: const Text('History',
                  style: TextStyle(
                      color: monopolyCream,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)))
        ]),
        if (widget.messages.isNotEmpty)
          Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                      '${widget.messages.last.who}: ${widget.messages.last.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: monopolyCream,
                          fontSize: 12,
                          fontWeight: FontWeight.w600))))
        else
          const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('Keep the conversation going between turns',
                      style:
                          TextStyle(color: Color(0xffc4b3a1), fontSize: 11)))),
        Row(children: [
          Expanded(
              child: TextField(
                  key: const Key('monopoly-chat-input'),
                  controller: widget.chatController,
                  enabled: widget.canChat && widget.connected,
                  maxLength: 300,
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => widget.onSendChat(),
                  style: const TextStyle(color: monopolyCream, fontSize: 14),
                  decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xff3b2b24),
                      hintText: !widget.connected
                          ? 'Chat reconnects when you are online'
                          : widget.canChat
                              ? 'Message the Huud…'
                              : 'Join the Huud to chat',
                      hintStyle: const TextStyle(
                          color: Color(0xffc3af9c), fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xff826341)))))),
          const SizedBox(width: 8),
          IconButton.filled(
              style: IconButton.styleFrom(
                  backgroundColor: monopolyGold, foregroundColor: monopolyInk),
              onPressed:
                  widget.canChat && widget.connected ? widget.onSendChat : null,
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Send to Huud chat')
        ]),
      ]));
}
