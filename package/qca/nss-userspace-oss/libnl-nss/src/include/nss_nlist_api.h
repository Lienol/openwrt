/*
 **************************************************************************
 * Copyright (c) 2019,2021 The Linux Foundation. All rights reserved.
 * Permission to use, copy, modify, and/or distribute this software for
 * any purpose with or without fee is hereby granted, provided that the
 * above copyright notice and this permission notice appear in all copies.
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
 * OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 **************************************************************************
 */

#ifndef __NSS_NLIST_H__
#define __NSS_NLIST_H__

/** @addtogroup chapter_nlist
 This chapter describes Netlink list APIs in the user space.
*/

/** @ingroup nss_nlist_datatypes
 * 	List node
 */
struct nss_nlist {
	struct nss_nlist *next;	/**< Next node. */
	struct nss_nlist *prev;	/**< Previous node. */
};

/** @addtogroup nss_nlist_functions @{ */

/**
 * Initializes the list node.
 *
 * @param[in] node List node.
 *
 * @return
 * None.
 */
static inline void nss_nlist_init(struct nss_nlist *node)
{
	node->next = node->prev = node;
}

/**
 * Gets the previous node.
 *
 * @param[in] node Previous node.
 *
 * @return
 * Previous node or head node.
 */
static inline struct nss_nlist *nss_nlist_prev(struct nss_nlist *node)
{
	return node->prev;
}

/**
 * Gets the next node.
 *
 * @param[in] node Next node.
 *
 * @return
 * Next node or head node.
 */
static inline struct nss_nlist *nss_nlist_next(struct nss_nlist *node)
{
	return node->next;
}

/**
 * Initializes the head node.
 *
 * @param[in] head Head of list.
 *
 * @return
 * None.
 */
static inline void nss_nlist_init_head(struct nss_nlist *head)
{
	nss_nlist_init(head);
}

/**
 * Returns first node in the list.
 *
 * @param[in] head List head.
 *
 * @return
 * First node.
 */
static inline struct nss_nlist *nss_nlist_first(struct nss_nlist *head)
{
	return nss_nlist_next(head);
}

/**
 * Returns last node in the list.
 *
 * @param[in] head List head.
 *
 * @return
 * Last node.
 */
static inline struct nss_nlist *nss_nlist_last(struct nss_nlist *head)
{
	return nss_nlist_prev(head);
}

/**
 * Checks if list is empty.
 *
 * @param[in] head List head.
 *
 * @return
 * TRUE if empty.
 */
static inline bool nss_nlist_isempty(struct nss_nlist *head)
{
	struct nss_nlist *first = nss_nlist_first(head);

	return first == head;
}

/**
 * Checks if corresponding node is the last node.
 *
 * @param[in] head Head node.
 * @param[in] node Node to check.
 *
 * @return
 * TRUE if it is the last node.
 */
static inline bool nss_nlist_islast(struct nss_nlist *head, struct nss_nlist *node)
{
	struct nss_nlist *last = nss_nlist_last(head);

	return last == node;
}

/**
 * Adds node to head of the list.
 *
 * @param[in] head List head.
 * @param[in] node Node to add.
 *
 * @return
 * None.
 */
static inline void nss_nlist_add_head(struct nss_nlist *head, struct nss_nlist *node)
{
	struct nss_nlist *first = nss_nlist_first(head);

	node->prev = head;
	node->next = first;

	first->prev = node;
	head->next = node;

}

/**
 * Adds node to tail of the list.
 *
 * @param[in] head List head.
 * @param[in] node Node to add.
 *
 * @return
 * None.
 */
static inline void nss_nlist_add_tail(struct nss_nlist *head, struct nss_nlist *node)
{
	struct nss_nlist *last = nss_nlist_last(head);

	node->next = head;
	node->prev = last;

	last->next = node;
	head->prev = node;
}

/**
 * Unlinks node from the list.
 *
 * @param[in] node Node to unlink.
 *
 * @return
 * None.
 */
static inline void nss_nlist_unlink(struct nss_nlist *node)
{
	struct nss_nlist *prev = nss_nlist_prev(node);
	struct nss_nlist *next = nss_nlist_next(node);

	prev->next = next;
	next->prev = prev;

	nss_nlist_init(node);
}

/** @} *//* end_addtogroup nss_nlist_functions */

/** @ingroup nss_nlist_macros
 * 	Lists node iterator.
 *
 * @hideinitializer
 * @param[in] _tmp Temporary node for assignment.
 * @param[in] _head Head node to start.
 *
 * @return
 * None.
 */
#define nss_nlist_iterate(_tmp, _head)			\
	for ((_tmp) = nss_nlist_first((_head));		\
		!nss_nlist_islast((_head), (_tmp));	\
		(_tmp) = nss_nlist_next((_tmp))

#endif /* __NSS_NLIST_H__ */
